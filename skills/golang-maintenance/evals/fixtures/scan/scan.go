package scan

import (
	"log"
	"sort"
)

func SortedNames(names []string) []string {
	out := append([]string(nil), names...)
	sort.Strings(out)
	return out
}

func LogValue(v interface{}) { log.Printf("value=%v", v) }
