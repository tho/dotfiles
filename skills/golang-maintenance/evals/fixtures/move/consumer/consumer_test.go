package consumer_test

import (
	"example.com/move/oldpkg"
	"testing"
)

func TestOldConsumer(t *testing.T) {
	var invoice oldpkg.Invoice = oldpkg.New(123)
	if invoice.Cents() != 123 {
		t.Fatalf("cents = %d", invoice.Cents())
	}
	if (oldpkg.Invoice{}).Cents() != 0 {
		t.Fatal("zero value changed")
	}
}
