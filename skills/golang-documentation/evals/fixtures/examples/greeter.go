// Package greeter formats greetings.
package greeter

// Client holds the prefix for a greeting.
type Client struct {
	prefix string
}

// New returns a client using prefix.
func New(prefix string) *Client {
	return &Client{prefix: prefix}
}

// Greet returns the prefix followed by a space and name.
func (c *Client) Greet(name string) string {
	return c.prefix + " " + name
}
