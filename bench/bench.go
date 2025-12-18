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
	http.HandleFunc("/log", handlerLogged)
	http.HandleFunc("/sse", sseHandler)

	log.Println("Go Datastar SSE Server running at http://localhost:8091")
	if err := http.ListenAndServe(":8091", nil); err != nil {
		log.Fatal(err)
	}
}

//go:embed index.html
var indexHTML string

//go:embed sse.html
var sseHTML string

func handler(w http.ResponseWriter, r *http.Request) {
	w.Write([]byte(indexHTML))
}

func handlerLogged(w http.ResponseWriter, r *http.Request) {
	t1 := time.Now().UnixMicro()
	w.Write([]byte(indexHTML))
	println("Go index handler took", time.Now().UnixMicro()-t1, "microseconds")
}

func sseHandler(w http.ResponseWriter, r *http.Request) {
	t1 := time.Now().UnixMicro()
	sse := datastar.NewSSE(w, r)
	sse.PatchElements(indexHTML)
	println("Go index handler took", time.Now().UnixMicro()-t1, "microseconds")
}
