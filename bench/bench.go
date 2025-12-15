package main

import (
	_ "embed" // 1. Import embed (the underscore is required)
	"log"
	"net/http"
	"time"

	"github.com/starfederation/datastar-go/datastar"
)

func main() {
	http.HandleFunc("/", handler)

	log.Println("Go Datastar SSE Server running at http://localhost:8091")
	if err := http.ListenAndServe(":8091", nil); err != nil {
		log.Fatal(err)
	}
}

//go:embed index.html
var indexHTML string

func handler(w http.ResponseWriter, r *http.Request) {
	t1 := time.Now().UnixMicro()
	sse := datastar.NewSSE(w, r)
	sse.PatchElements(indexHTML)
	log.Println("Go handler took", time.Now().UnixMicro()-t1, "microseconds")
}
