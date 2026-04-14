package main

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/mmcloughlin/geohash"
)

// CaptainState represents a live captain's position and availability
type CaptainState struct {
	ID       string    `json:"id"`
	Lat      float64   `json:"lat"`
	Lng      float64   `json:"lng"`
	Status   string    `json:"status"` // "available", "busy"
	LastSeen time.Time `json:"-"`
}

// LiveManager governs the memory-resident matchmaking state
type LiveManager struct {
	sync.RWMutex
	Captains    map[string]*CaptainState
	Connections map[string]*websocket.Conn // Tracks active WS for each user
}

var (
	manager = &LiveManager{
		Captains:    make(map[string]*CaptainState),
		Connections: make(map[string]*websocket.Conn),
	}
	upgrader = websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}
)

func (m *LiveManager) UpdateCaptain(id string, lat, lng float64, status string) {
	m.Lock()
	defer m.Unlock()
	m.Captains[id] = &CaptainState{
		ID:       id,
		Lat:      lat,
		Lng:      lng,
		Status:   status,
		LastSeen: time.Now(),
	}
}

func (m *LiveManager) GetNearbyCaptains(lat, lng float64) []*CaptainState {
	m.RLock()
	defer m.RUnlock()

	// Simple Geohash-based filtering (Precision 5 = ~4.9km x 4.9km)
	hash := geohash.Encode(lat, lng)[:5]
	var results []*CaptainState

	for _, c := range m.Captains {
		// Only show available captains seen in the last 60 seconds
		if c.Status == "available" && time.Since(c.LastSeen) < 60*time.Second {
			cHash := geohash.Encode(c.Lat, c.Lng)[:5]
			if cHash == hash {
				results = append(results, c)
			}
		}
	}
	return results
}

// WSHandler handles the live location stream
func WSHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	
	var currentUserID string
	defer func() {
		if currentUserID != "" {
			manager.Lock()
			delete(manager.Connections, currentUserID)
			manager.Unlock()
		}
		conn.Close()
	}()

	for {
		_, message, err := conn.ReadMessage()
		if err != nil {
			break
		}

		var msg map[string]interface{}
		if err := json.Unmarshal(message, &msg); err != nil {
			continue
		}

		msgType, _ := msg["type"].(string)

		switch msgType {
		case "identify":
			// Associate connection with User ID
			id, _ := msg["id"].(string)
			if id != "" {
				currentUserID = id
				manager.Lock()
				manager.Connections[id] = conn
				manager.Unlock()
			}

		case "update_location":
			// Process Captain Location Update
			id, _ := msg["id"].(string)
			lat, _ := msg["lat"].(float64)
			lng, _ := msg["lng"].(float64)
			status, _ := msg["status"].(string)
			manager.UpdateCaptain(id, lat, lng, status)

		case "get_nearby":
			// Process Rider Query
			lat, _ := msg["lat"].(float64)
			lng, _ := msg["lng"].(float64)
			nearby := manager.GetNearbyCaptains(lat, lng)
			
			resp := map[string]interface{}{
				"type":     "nearby_captains",
				"captains": nearby,
			}
			conn.WriteJSON(resp)
		}
	}
}
