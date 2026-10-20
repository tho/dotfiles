package greeter_test

import (
	"example.com/greeter"
	"fmt"
)

func ExampleClient_Greet() {
	client := greeter.New()
	fmt.Println(client.Greet("Ada"))
	// Output: Hello Ada
}

func ExampleClient_Greet_quiet() {
	client := greeter.New("Hi")
	fmt.Println(client.Greet("Bo"))
}
