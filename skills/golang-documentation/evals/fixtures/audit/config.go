// Package portdoc selects a port from available configuration.
package portdoc

import "strconv"

// Port returns the selected port. Explicit flags override environment values.
func Port(filePort, flagPort int, flagSet bool, envPort string) (int, error) {
	port := 8080
	if filePort != 0 {
		port = filePort
	}
	if flagSet {
		port = flagPort
	}
	if envPort != "" {
		parsed, err := strconv.Atoi(envPort)
		if err != nil {
			return 0, err
		}
		port = parsed
	}
	return port, nil
}
