package record_test

import (
	"encoding/json"
	record "example.com/rename"
	"testing"
)

func TestContract(t *testing.T) {
	r := record.Record{Label: "alpha"}
	b, err := json.Marshal(r)
	if err != nil || string(b) != `{"label":"alpha"}` {
		t.Fatalf("JSON %s, err %v", b, err)
	}
	s, err := record.Render(r)
	if err != nil || s != "record=alpha" {
		t.Fatalf("render %q, err %v", s, err)
	}
}
