# CliquePix transcoder dev convenience targets
#
# Run from backend/transcoder/

.PHONY: help install build clean docker-build docker-test transcode-local push deploy

# Default target
help:
	@echo "CliquePix transcoder targets:"
	@echo ""
	@echo "  make install        - Install npm dependencies"
	@echo "  make build          - Compile TypeScript to dist/"
	@echo "  make clean          - Remove dist/ and test-output/"
	@echo ""
	@echo "  make docker-build   - Build the Docker image (cliquepix-transcoder:local)"
	@echo "  make docker-test INPUT=sample-videos/iphone-h264-1080p.mov"
	@echo "                      - Run the container locally on a sample video"
	@echo ""
	@echo "  make transcode-local INPUT=sample-videos/iphone-h264-1080p.mov"
	@echo "                      - Run the runner directly via node (no Docker)"
	@echo ""
	@echo "  make push           - Build and push to ACR (cracliquepix.azurecr.io)"
	@echo "  make deploy         - Push image and update Container Apps Job"

install:
	npm install

build:
	npm run build

clean:
	npm run clean
	rm -rf test-output

docker-build:
	npm run build
	docker build -t cliquepix-transcoder:local .

docker-test: docker-build
	@if [ -z "$(INPUT)" ]; then \
		echo "ERROR: INPUT is required. Usage: make docker-test INPUT=sample-videos/iphone-h264-1080p.mov"; \
		exit 1; \
	fi
	@if [ ! -f "$(INPUT)" ]; then \
		echo "ERROR: Input file not found: $(INPUT)"; \
		exit 1; \
	fi
	@mkdir -p test-output
	@FILENAME=$$(basename "$(INPUT)") && \
	docker run --rm \
		-v "$$(pwd)/sample-videos:/input:ro" \
		-v "$$(pwd)/test-output:/output" \
		-e LOCAL_MODE=true \
		-e LOCAL_INPUT_FILE="/input/$$FILENAME" \
		-e LOCAL_OUTPUT_DIR=/output \
		cliquepix-transcoder:local
	@echo ""
	@echo "Done! Outputs in test-output/"
	@ls -la test-output/

transcode-local: build
	@if [ -z "$(INPUT)" ]; then \
		echo "ERROR: INPUT is required. Usage: make transcode-local INPUT=sample-videos/iphone-h264-1080p.mov"; \
		exit 1; \
	fi
	@mkdir -p test-output
	LOCAL_MODE=true \
	LOCAL_INPUT_FILE="$(INPUT)" \
	LOCAL_OUTPUT_DIR=test-output \
	node dist/runner.js

push: docker-build
	az acr login --name cracliquepix
	docker tag cliquepix-transcoder:local cracliquepix.azurecr.io/cliquepix-transcoder:latest
	docker push cracliquepix.azurecr.io/cliquepix-transcoder:latest
	@echo ""
	@echo "Image pushed. To deploy to Container Apps Job:"
	@echo "  make deploy"

deploy: push
	az containerapp job update \
		--name caj-cliquepix-transcoder \
		--resource-group rg-cliquepix-prod \
		--image cracliquepix.azurecr.io/cliquepix-transcoder:latest
