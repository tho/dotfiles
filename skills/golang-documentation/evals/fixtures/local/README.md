# Labels

Go 1.22 is the supported minimum. The current checkout has an unreleased API change.

```go
package main

import (
    "fmt"
    "example.com/labels"
)

func main() {
    fmt.Println(labels.Format(" Ada "))
}
```

Expected output: `user:Ada`.
