package main

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"math"
	"testing"

	pb "golocationspoofer/pb"
	"google.golang.org/protobuf/proto"
)

func TestDeserializeRealRequest(t *testing.T) {
	// This captured request has an empty payload: it cannot be a Wi-Fi fixture.
	requestBytes, err := hex.DecodeString("0001000a656e2d3030315f3030310013636f6d2e6170706c652e6c6f636174696f6e64000a32362e322e3233433535000000020000000002000000")
	if err != nil { t.Fatal(err) }
	arpc := ArpcDeserialize(requestBytes)
	if arpc == nil { t.Fatal("Failed to deserialize ARPC") }
	if arpc.Version != "1" || arpc.FunctionId != 2 || arpc.AppIdentifier != "com.apple.locationd" {
		t.Fatalf("Unexpected decoded header: %+v", arpc)
	}
	wloc := &pb.AppleWLoc{}
	if err := proto.Unmarshal(arpc.Payload, wloc); err != nil { t.Fatal(err) }
	if len(wloc.WifiDevices) != 0 { t.Fatal("Captured empty payload unexpectedly contains Wi-Fi devices") }
}

func TestFullRoundTrip(t *testing.T) {
	// Build a real Wi-Fi fixture instead of expecting devices in the empty capture.
	request := &pb.AppleWLoc{WifiDevices: []*pb.WifiDevice{{Bssid: "aa:bb:cc:dd:ee:ff"}}}
	payload, err := proto.Marshal(request)
	if err != nil { t.Fatal(err) }
	requestBytes := ArpcSerialize(&ArpcRequest{Version: "1", Locale: "en-001_001", AppIdentifier: "com.apple.locationd", OsVersion: "26.2.23C55", FunctionId: 2, Payload: payload})
	arpc := ArpcDeserialize(requestBytes)
	if arpc == nil { t.Fatal("Failed to deserialize ARPC") }
	wloc := &pb.AppleWLoc{}
	if err := proto.Unmarshal(arpc.Payload, wloc); err != nil { t.Fatal(err) }
	if len(wloc.WifiDevices) != 1 { t.Fatal("Expected one Wi-Fi device") }
	lat, lon := IntFromCoord(51.510420), IntFromCoord(-3.218306)
	for _, device := range wloc.WifiDevices {
		if device.Location == nil { device.Location = &pb.Location{} }
		device.Location.Latitude = &lat
		device.Location.Longitude = &lon
		device.Location.HorizontalAccuracy = p64(39)
		device.Location.VerticalAccuracy = p64(1000)
		device.Location.Altitude = p64(530)
		device.Location.UnknownValue4 = p64(3)
		device.Location.MotionActivityType = p64(63)
		device.Location.MotionActivityConfidence = p64(467)
	}
	wloc.NumCellResults, wloc.NumWifiResults, wloc.DeviceType = nil, nil, nil
	initialBytes, _ := hex.DecodeString("0001000000010000")
	responseBytes, err := SerializeProto(wloc, initialBytes)
	if err != nil { t.Fatal(err) }
	if len(responseBytes) < 10 || !bytes.Equal(responseBytes[:8], initialBytes) { t.Fatal("Incorrect response header") }
	payloadLen := int(binary.BigEndian.Uint16(responseBytes[8:10]))
	if payloadLen != len(responseBytes)-10 { t.Fatalf("Payload length mismatch: %d vs %d", payloadLen, len(responseBytes)-10) }
	decoded := &pb.AppleWLoc{}
	if err := proto.Unmarshal(responseBytes[10:], decoded); err != nil { t.Fatal(err) }
	if !proto.Equal(wloc, decoded) { t.Fatal("Response protobuf did not survive round trip") }
}

func TestCoordinateEncoding(t *testing.T) {
	for _, coord := range []float64{51.510420, -3.218306, 0, 90, -180} {
		if math.Abs(CoordFromInt(IntFromCoord(coord))-coord) > 1.1e-8 { t.Fatalf("Coordinate round trip failed: %v", coord) }
	}
	for _, n := range []int64{0, 1, -1, 5151042000, -321830600} {
		want := uint64(n<<1) ^ uint64(n>>63)
		if encodeZigzag(n) != want { t.Fatalf("Incorrect zigzag for %d", n) }
		encoded := appendVarint(nil, want)
		got, count := binary.Uvarint(encoded)
		if count != len(encoded) || got != want { t.Fatalf("Incorrect varint for %d", n) }
	}
}

func TestFieldPresence(t *testing.T) {
	wloc := &pb.AppleWLoc{WifiDevices: []*pb.WifiDevice{{Bssid: "aa:bb:cc:dd:ee:ff", Location: &pb.Location{Latitude: p64(5151042000), Longitude: p64(-321830600)}}}}
	before, err := proto.Marshal(wloc)
	if err != nil { t.Fatal(err) }
	wloc.NumCellResults, wloc.NumWifiResults, wloc.DeviceType = nil, nil, nil
	after, err := proto.Marshal(wloc)
	if err != nil { t.Fatal(err) }
	if !bytes.Equal(before, after) { t.Fatal("Explicit nil fields changed protobuf output") }
}
