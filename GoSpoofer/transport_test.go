package main

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	pb "golocationspoofer/pb"
	"google.golang.org/protobuf/encoding/protowire"
	"google.golang.org/protobuf/proto"
)

func TestARPCRoundTripPreservesFunctionAndPayload(t *testing.T) {
	for _, payload := range [][]byte{nil, {}, {1, 2, 3}} {
		original := &ArpcRequest{Version: "1", Locale: "en", AppIdentifier: "test", OsVersion: "18.0", FunctionId: 7, Payload: payload}
		got := ArpcDeserialize(ArpcSerialize(original))
		if got == nil || got.FunctionId != original.FunctionId || !bytes.Equal(got.Payload, payload) { t.Fatalf("Invalid round trip: %+v", got) }
	}
}

func TestARPCRejectsEveryTruncatedPrefix(t *testing.T) {
	encoded := ArpcSerialize(&ArpcRequest{Version: "1", Locale: "en", AppIdentifier: "test", OsVersion: "18.0", FunctionId: 2, Payload: []byte{1, 2, 3}})
	for i := 0; i < len(encoded); i++ {
		if got := ArpcDeserialize(encoded[:i]); got != nil { t.Fatalf("Accepted truncated request at %d/%d", i, len(encoded)) }
	}
	if ArpcDeserialize(encoded) == nil { t.Fatal("Rejected complete request") }
}

func TestInvalidLocationRequestsKeepTheirBody(t *testing.T) {
	invalidProto := ArpcSerialize(&ArpcRequest{Version: "1", Locale: "en", AppIdentifier: "test", OsVersion: "18.0", FunctionId: 2, Payload: []byte{0xff}})
	for _, body := range [][]byte{[]byte("invalid ARPC"), invalidProto} {
		req := httptest.NewRequest(http.MethodPost, "https://gs-loc.apple.com/clls/wloc", bytes.NewReader(body))
		forward, response := handleLocationRequest(req)
		if forward != req || response != nil { t.Fatal("Malformed payload should remain a passthrough request") }
		got, err := io.ReadAll(forward.Body)
		forward.Body.Close()
		if err != nil || !bytes.Equal(got, body) { t.Fatalf("Forwarded body lost: %q, %v", got, err) }
	}
}

type failingRequestBody struct{}
func (failingRequestBody) Read([]byte) (int, error) { return 0, errors.New("read failed") }
func (failingRequestBody) Close() error { return nil }

func TestBodyReadFailureIsNotForwarded(t *testing.T) {
	req := httptest.NewRequest(http.MethodPost, "https://gs-loc.apple.com/clls/wloc", nil)
	req.Body = failingRequestBody{}
	_, response := handleLocationRequest(req)
	if response == nil || response.StatusCode != http.StatusBadRequest { t.Fatal("An unreadable body must not be forwarded as a successful request") }
	response.Body.Close()
}

func TestCoordinateRewritePreservesOtherFields(t *testing.T) {
	unknown := protowire.AppendTag(nil, 100, protowire.BytesType)
	unknown = protowire.AppendBytes(unknown, []byte("preserve-me"))
	loc := &pb.Location{Latitude: p64(1), Longitude: p64(2), HorizontalAccuracy: p64(39), Altitude: p64(530)}
	loc.ProtoReflect().SetUnknown(unknown)
	original := &pb.AppleWLoc{WifiDevices: []*pb.WifiDevice{{Bssid: "aa:bb:cc:dd:ee:ff", Location: loc}, {Bssid: "11:22:33:44:55:66"}}}
	original.ProtoReflect().SetUnknown(unknown)
	payload, err := proto.Marshal(original)
	if err != nil { t.Fatal(err) }
	lat, lon := IntFromCoord(51.5), IntFromCoord(-3.2)
	out, count := rewriteAppleWLocCoords(payload, lat, lon)
	if count != 4 { t.Fatalf("Expected four rewritten/injected coordinates, got %d", count) }
	decoded := &pb.AppleWLoc{}
	if err := proto.Unmarshal(out, decoded); err != nil { t.Fatal(err) }
	for _, device := range decoded.WifiDevices {
		if device.Location.GetLatitude() != lat || device.Location.GetLongitude() != lon { t.Fatal("Missing or incorrect rewritten coordinates") }
	}
	if decoded.WifiDevices[0].Location.GetHorizontalAccuracy() != 39 || decoded.WifiDevices[0].Location.GetAltitude() != 530 { t.Fatal("Unrelated location fields changed") }
	if !bytes.Equal(decoded.ProtoReflect().GetUnknown(), unknown) || !bytes.Equal(decoded.WifiDevices[0].Location.ProtoReflect().GetUnknown(), unknown) { t.Fatal("Unknown protobuf fields were lost") }
}
