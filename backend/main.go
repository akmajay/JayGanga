package main

import (
	"log"
	"os"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
)

func main() {
	app := pocketbase.New()

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
				&core.NumberField{Name: "pickup_lat", Required: true},
				&core.NumberField{Name: "pickup_lng", Required: true},
				&core.NumberField{Name: "drop_lat", Required: true},
				&core.NumberField{Name: "drop_lng", Required: true},
				&core.NumberField{Name: "distance_km", Required: true},
				&core.NumberField{Name: "agreed_fare", Required: true},
				&core.NumberField{Name: "start_otp"},
				&core.SelectField{Name: "status", Values: []string{"matched", "ongoing", "completed", "cancelled"}, DefaultValue: "matched"},
			)
			if err := app.Save(rides); err != nil {
				return err
			}
		}

		return e.Next()
	})

	// 2. Custom Routing (e.g., Static Files)
	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		se.Router.GET("/{path...}", apis.Static(os.DirFS("./pb_public"), false))
		return se.Next()
	})

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
