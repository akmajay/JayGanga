PROJECT REPORT: Zero-Commission Ride-Hailing Platform
1. Core Philosophy
package : com.ride.jayganga
android app for rider and captain and web app for admin (last)
Google Sign in for rider and captain and admin
Proper RLS
Use PocketBase (latest 0.36.8) with custom  go backend not goja.
 

A peer-to-peer, zero-commission mobility network. The platform acts strictly as a lightweight matchmaking engine. To maintain near-zero server costs, heavy compute (distance calculation, routing) is offloaded to the client devices, and database writes are restricted to permanent records only.

2. Technical Stack
Frontend (Rider & Captain): Flutter (Dart) using a single codebase.

Backend Server: Custom Golang (Go).

Database: PocketBase (SQLite) embedded directly within the Go backend.

Infrastructure: 1x $5 Bare-Metal VPS (e.g., Hetzner/DigitalOcean) per city. OS: Ubuntu/Debian.

Visual Map UI: Google Maps Flutter SDK (Free Tier).

Distance/Pricing Engine: Client-side Haversine Formula * 1.4 multiplier.

Payments: Direct P2P UPI (No gateway integration).

3. Database Schema (PocketBase)
You only need three primary collections for Version 1.0.

A. users (Riders)
id (String) - Auto-generated

phone (String) - Unique

name (String)

rating (Number) - Default 5.0

B. captains (Drivers)
id (String) - Auto-generated

phone (String) - Unique

name (String)

vehicle_type (Select: Bike, Auto, Cab)

vehicle_number (String)

rating (Number) - Default 5.0

kyc_status (Select: Pending, Approved, Blocked)

C. rides (The Permanent Log)
id (String) - Auto-generated

rider_id (Relation -> users)

captain_id (Relation -> captains)

pickup_lat (Number)

pickup_lng (Number)

drop_lat (Number)

drop_lng (Number)

distance_km (Number)

agreed_fare (Number)

start_otp (Number) - 4-digit PIN generated on creation

status (Select: matched, ongoing, completed, cancelled)

created / updated (Timestamps)

4. Server RAM Architecture (The Go Backend)
The Go backend avoids database writes for live data. It relies on three primary global variables (Maps) secured by sync.RWMutex.

ActiveConnections map[string]*websocket.Conn

Stores the live network connection mapped to the user/captain's ID.

CaptainLocations map[string]LocationData

Stores lat, lng, and geohash. Updated every 10 seconds by idle Captains.

ActiveBids map[string]BidData

Temporarily holds ride requests and negotiations. Deleted the moment a match is made or 3 minutes pass.

5. The Ride Lifecycle (State Machine)
Phase 1: Idle & Discovery
Captain App: Opens WebSocket. Sends location payload {"lat": X, "lng": Y} every 10 seconds.

Go Server: Updates CaptainLocations in RAM.

Rider App: Drops Pickup and Drop pins. Calculates distance locally (Haversine * 1.4). Suggests base fare.

Phase 2: The Bidding War
Rider App: User taps "Find Ride". App connects to WebSocket and sends: {"action": "new_bid", "pickup": [X,Y], "drop": [A,B], "fare": 100}.

Go Server: Calculates the Geohash for pickup [X,Y]. Finds all Captains in that Geohash from RAM. Relays the bid to those specific WebSockets.

Captain App: Displays bid. Captain taps "+₹20". App sends: {"action": "counter_bid", "fare": 120}.

Go Server: Relays counter-bid to Rider.

Phase 3: The Match & Approach
Rider App: Taps "Accept" on Captain A's profile.

Go Server: * Executes DB Write #1: Creates the rides record with status matched and generates a 4-digit start_otp.

Notifies Captain A of the match. Releases other Captains.

Captain App: Navigates to Pickup. Sends location via WebSocket every 5 seconds so Rider can track approach.

Phase 4: The Handshake & "Offline" Ride
Captain App: Arrives at pickup. Asks Rider for the 4-digit OTP. Captain enters it into the app.

Go Server: Validates OTP via HTTP POST request.

Executes DB Write #2: Updates ride status to ongoing.

CRITICAL STEP: Server forcefully closes the WebSockets for both Rider and Captain to free up RAM. Deletes Captain from CaptainLocations.

Captain App: Triggers google.navigation:q=lat,lng to open native Google Maps for turn-by-turn navigation.

Phase 5: Completion & P2P Payment
Captain App: Arrives at destination (Geofence validation passes). Captain taps "End Ride". App generates a UPI QR code or triggers UPI Intent.

Rider App: Rider pays via PhonePe/GPay directly to Captain's bank.

Captain App: Captain verifies bank SMS, taps "Payment Received".

Makes a final HTTP POST request to server.

Go Server:

Executes DB Write #3: Updates ride status to completed.

6. Frontend Background Handling (Crucial)
Flutter Background Service: The Captain app MUST utilize a foreground service package. When waiting for rides, it must display a persistent sticky notification (e.g., "Online: Ready for rides"). If you do not code this, Android/iOS will kill your WebSocket connection within 60 seconds to save battery, and your Captains will receive no ride requests.