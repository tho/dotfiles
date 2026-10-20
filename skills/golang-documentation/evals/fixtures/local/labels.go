// Package labels formats display labels.
package labels

import "strings"

// Format returns prefix followed by a colon and the trimmed name.
func Format(prefix, name string) string {
	return prefix + ":" + strings.TrimSpace(name)
}
