package clone_test

import (
	clone "example.com/modernize"
	"testing"
)

func TestCloneContract(t *testing.T) {
	for _, src := range []map[string]int{nil, {}, {"a": 1}} {
		dst := clone.Clone(src)
		dst["new"] = 2
		if _, ok := src["new"]; ok {
			t.Fatal("clone shares source map")
		}
		if src != nil && src["a"] != dst["a"] {
			t.Fatal("value lost")
		}
	}
}
