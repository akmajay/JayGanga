package main

import (
	"log"
	"os"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"google.golang.org/api/idtoken"
)

func main() {
	app := pocketbase.New()

	// Configuration (In production, move these to Env variables)
	googleClientID := "621062699038-placeholder.apps.googleusercontent.com" 

	// 1. Initialize Collections programmatically
	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		// Create Users collection (if needed)
		// Note: Users is a default collection, we can extend it via Admin UI or code.
		
		// Create Captains collection
		captains, _ := app.FindCollectionByNameOrId("captains")
		if captains == nil {
			captains = core.NewEmptyCollection("captains")
			captains.Fields.Add(
				&core.TextField{Name: "phone", Required: true, Unique: true},
				&core.TextField{Name: "name", Required: true},
				&core.SelectField{Name: "vehicle_type", Values: []string{"Bike", "Auto", "Cab"}, Required: true},
				&core.TextField{Name: "vehicle_number", Required: true},
				&core.NumberField{Name: "rating", DefaultValue: 5.0},
				&core.SelectField{Name: "kyc_status", Values: []string{"Pending", "Approved", "Blocked"}, DefaultValue: "Pending"},
			)
			captains.ListRule = core.Pointer("@request.auth.id != ''")
			captains.ViewRule = core.Pointer("@request.auth.id != ''")
			captains.CreateRule = core.Pointer("@request.auth.id != ''")
			captains.UpdateRule = core.Pointer("@request.auth.id != '' && id = @request.auth.id")
			
			if err := app.Save(captains); err != nil {
				return err
			}
		}

		// Create Rides collection
		rides, _ := app.FindCollectionByNameOrId("rides")
		if rides == nil {
			rides = core.NewEmptyCollection("rides")
			rides.Fields.Add(
				&core.RelationField{Name: "rider_id", CollectionId: "_pb_users_auth_", MaxSelect: 1, Required: true},
				&core.RelationField{Name: "captain_id", CollectionId: captains.Id, MaxSelect: 1},
				&core.TextField{Name: "pickup_address", Required: true},
				&core.TextField{Name: "drop_address", Required: true},
				&core.NumberField{Name: "pickup_lat", Required: true},
				&core.NumberField{Name: "pickup_lng", Required: true},
				&core.NumberField{Name: "drop_lat", Required: true},
				&core.NumberField{Name: "drop_lng", Required: true},
				&core.NumberField{Name: "distance_km", Required: true},
				&core.NumberField{Name: "agreed_fare", Required: true},
				&core.NumberField{Name: "start_otp"},
				&core.SelectField{Name: "status", Values: []string{"matched", "ongoing", "completed", "cancelled"}, DefaultValue: "matched"},
			)
			rides.ListRule = core.Pointer("rider_id = @request.auth.id || captain_id = @request.auth.id")
			rides.ViewRule = core.Pointer("rider_id = @request.auth.id || captain_id = @request.auth.id")
			rides.CreateRule = core.Pointer("@request.auth.id != ''")
			rides.UpdateRule = core.Pointer("rider_id = @request.auth.id || captain_id = @request.auth.id")

			if err := app.Save(rides); err != nil {
				return err
			}
		}

		// Create Bids collection
		bids, _ := app.FindCollectionByNameOrId("bids")
		if bids == nil {
			bids = core.NewEmptyCollection("bids")
			bids.Fields.Add(
				&core.RelationField{Name: "ride_id", CollectionId: rides.Id, MaxSelect: 1, Required: true},
				&core.RelationField{Name: "captain_id", CollectionId: captains.Id, MaxSelect: 1, Required: true},
				&core.NumberField{Name: "amount", Required: true},
				&core.SelectField{Name: "status", Values: []string{"pending", "accepted", "rejected"}, DefaultValue: "pending"},
			)
			bids.ListRule = core.Pointer("ride_id.rider_id = @request.auth.id || captain_id = @request.auth.id")
			bids.ViewRule = core.Pointer("ride_id.rider_id = @request.auth.id || captain_id = @request.auth.id")
			bids.CreateRule = core.Pointer("@request.auth.id != ''")

			if err := app.Save(bids); err != nil {
				return err
			}
		}

		return e.Next()
	})

	// 2. Custom Routing (Auth & Realtime)
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		// Native Google Auth Endpoint
		se.Router.POST("/api/ride/auth-google", func(e *core.RequestEvent) error {
			data := struct {
				IDToken string `json:"idToken"`
			}{}
			if err := e.BindBody(&data); err != nil {
				return apis.NewBadRequestError("Missing idToken", nil)
			}

			// Verify the Google ID Token
			payload, err := idtoken.Validate(e.Request.Context(), data.IDToken, googleClientID)
			if err != nil {
				return apis.NewBadRequestError("Invalid google token", err)
			}

			email := payload.Claims["email"].(string)
			name := payload.Claims["name"].(string)

			// Find or Create User
			users, _ := app.FindCollectionByNameOrId("users")
			record, err := app.FindAuthRecordByEmail("users", email)
			if err != nil {
				// User doesn't exist, create one
				record = core.NewRecord(users)
				record.Set("email", email)
				record.Set("name", name)
				record.SetVerified(true)
				// Set a random password for auth records (required by PocketBase)
				record.SetPassword(core.RandomString(30))
				
				if err := app.Save(record); err != nil {
					return err
				}
			}

			// Return the standard PocketBase Auth Response (JWT + User data)
			return apis.RecordAuthResponse(app, record, nil)
		})

		// Live Tracking WebSocket
		se.Router.GET("/api/ride/ws", WSHandler)

		// Secure OTP Verification Endpoint
		se.Router.POST("/api/ride/start", func(e *core.RequestEvent) error {
			data := struct {
				RideID string `json:"rideId"`
				OTP    int    `json:"otp"`
			}{}
			if err := e.BindBody(&data); err != nil {
				return apis.NewBadRequestError("Missing data", nil)
			}

			ride, err := app.FindRecordById("rides", data.RideID)
			if err != nil {
				return apis.NewNotFoundError("Ride not found", err)
			}

			if ride.GetInt("start_otp") != data.OTP {
				return apis.NewBadRequestError("Invalid OTP", nil)
			}

			// OTP matches! Start the ride.
			ride.Set("status", "ongoing")
			if err := app.Save(ride); err != nil {
				return err
			}

			return e.JSON(http.StatusOK, map[string]string{"message": "Ride started"})
		})

		return se.Next()
	})

	// 3. Matchmaking Hooks
	app.OnRecordAfterCreateRequest("rides").BindFunc(func(e *core.RecordRequestEvent) error {
		// A new ride was requested!
		pickupLat := e.Record.GetFloat("pickup_lat")
		pickupLng := e.Record.GetFloat("pickup_lng")

		// 3.1 Generate OTP (Simple 4-digit)
		otp := core.RandomRange(1000, 9999)
		e.Record.Set("start_otp", otp)
		if err := app.Save(e.Record); err != nil {
			return err
		}

		// 3.2 Find nearby captains
		nearby := manager.GetNearbyCaptains(pickupLat, pickupLng)

		// Notify them via WebSocket
		notification := map[string]interface{}{
			"type":    "new_ride_available",
			"ride_id": e.Record.Id,
			"pickup":  e.Record.GetString("pickup_address"),
			"drop":    e.Record.GetString("drop_address"),
			"lat":     pickupLat,
			"lng":     pickupLng,
		}

		manager.RLock()
		defer manager.RUnlock()
		for _, cap := range nearby {
			if conn, ok := manager.Connections[cap.ID]; ok {
				conn.WriteJSON(notification)
			}
		}

		return e.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
