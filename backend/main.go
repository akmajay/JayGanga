package main

import (
	"log"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/security"
	"google.golang.org/api/idtoken"
)

func main() {
	app := pocketbase.New()

	// Configuration (In production, move these to Env variables)
	googleClientID := "621062699038-placeholder.apps.googleusercontent.com"

	// 1. Initialize Collections programmatically
	app.OnBootstrap().BindFunc(func(e *core.BootstrapEvent) error {
		// Run core bootstrap first
		if err := e.Next(); err != nil {
            return err
        }

		// Create Captains collection
		captains, _ := app.FindCollectionByNameOrId("captains")
		if captains == nil {
			captains = core.NewBaseCollection("captains")
			captains.Fields.Add(
				&core.TextField{Name: "phone", Required: true},
				&core.TextField{Name: "name", Required: true},
				&core.SelectField{Name: "vehicle_type", Values: []string{"Bike", "Auto", "Cab"}, Required: true},
				&core.TextField{Name: "vehicle_number", Required: true},
				&core.NumberField{Name: "rating"},
				&core.SelectField{Name: "kyc_status", Values: []string{"Pending", "Approved", "Blocked"}},
			)
			captains.Indexes = append(captains.Indexes, "CREATE UNIQUE INDEX idx_captains_phone ON captains (phone)")
			
			rule := "@request.auth.id != ''"
			captains.ListRule = &rule
			captains.ViewRule = &rule
			captains.CreateRule = &rule
			
			if err := app.Save(captains); err != nil {
				log.Println("Error saving captains:", err)
			}
		}

		// Create Rides collection
		rides, _ := app.FindCollectionByNameOrId("rides")
		if rides == nil {
			rides = core.NewBaseCollection("rides")
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
				&core.SelectField{Name: "status", Values: []string{"matched", "ongoing", "completed", "cancelled"}},
			)
			
			rule := "rider_id = @request.auth.id || captain_id = @request.auth.id"
			createRule := "@request.auth.id != ''"
			rides.ListRule = &rule
			rides.ViewRule = &rule
			rides.CreateRule = &createRule
			rides.UpdateRule = &rule

			if err := app.Save(rides); err != nil {
				log.Println("Error saving rides:", err)
			}
		}

		return nil
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

			payload, err := idtoken.Validate(e.Request.Context(), data.IDToken, googleClientID)
			if err != nil {
				return apis.NewBadRequestError("Invalid google token", err)
			}

			email := payload.Claims["email"].(string)
			name := payload.Claims["name"].(string)

			record, err := app.FindAuthRecordByEmail("users", email)
			if err != nil {
				users, _ := app.FindCollectionByNameOrId("users")
				record = core.NewRecord(users)
				record.Set("email", email)
				record.Set("name", name)
				record.SetVerified(true)
				record.SetPassword(security.RandomString(30))
				
				if err := app.Save(record); err != nil {
					return err
				}
			}

			return apis.RecordAuthResponse(e, record, "users", nil)
		})

		// Live Tracking WebSocket
		se.Router.GET("/api/ride/ws", func(e *core.RequestEvent) error {
			WSHandler(e.Response, e.Request)
			return nil
		})

		return se.Next()
	})

	// 3. Matchmaking Hooks
	app.OnRecordCreate("rides").BindFunc(func(e *core.RecordEvent) error {
		err := e.Next() 
		if err != nil {
			return err
		}

		pickupLat := e.Record.GetFloat("pickup_lat")
		pickupLng := e.Record.GetFloat("pickup_lng")

		// Notify nearby captains
		nearby := manager.GetNearbyCaptains(pickupLat, pickupLng)

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

		return nil
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
