.PHONY: build clean docker

build:
	go build -ldflags="-s -w" -o portainer-mcp-server .

clean:
	rm -f portainer-mcp-server

docker:
	docker build -t portainer-mcp-server .

run: build
	./portainer-mcp-server -portainer-url $(PORTAINER_URL) -portainer-token $(PORTAINER_TOKEN)