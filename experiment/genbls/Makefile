all: main.go
	go build -o main main.go

test: main
	./main -host hosts.json -key 1 -shard 2 -slot 10

clean:
	rm -rf files
	rm main

PHONY: test clean
