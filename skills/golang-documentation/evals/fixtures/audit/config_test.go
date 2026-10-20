package portdoc_test

import (
	"example.com/portdoc"
	"fmt"
)

func ExamplePort() {
	port, err := portdoc.Port(8000, 9000, true, "7000")
	fmt.Println(port, err)
	// Output: 7000 <nil>
}

func ExamplePort_emptyEnv() {
	port, err := portdoc.Port(8000, 9000, true, "")
	fmt.Println(port, err)
	// Output: 9000 <nil>
}
