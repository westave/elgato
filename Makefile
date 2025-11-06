.PHONY: build run clean install help

# Build configuration
BUILD_DIR = .build/release
APP_NAME = ElgatoCameraControl
INSTALL_DIR = /usr/local/bin

help:
	@echo "Elgato Camera Control - Makefile"
	@echo ""
	@echo "Available commands:"
	@echo "  make build    - Build the application in release mode"
	@echo "  make run      - Build and run the application"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make install  - Install to $(INSTALL_DIR)"
	@echo "  make help     - Show this help message"

build:
	@echo "Building $(APP_NAME)..."
	swift build -c release
	@echo "✅ Build complete: $(BUILD_DIR)/$(APP_NAME)"

run: build
	@echo "Running $(APP_NAME)..."
	$(BUILD_DIR)/$(APP_NAME)

clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -rf .build
	@echo "✅ Clean complete"

install: build
	@echo "Installing $(APP_NAME) to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@cp $(BUILD_DIR)/$(APP_NAME) $(INSTALL_DIR)/
	@chmod +x $(INSTALL_DIR)/$(APP_NAME)
	@echo "✅ Installed to $(INSTALL_DIR)/$(APP_NAME)"
	@echo ""
	@echo "To run: $(APP_NAME)"
	@echo "To add to Login Items: System Settings → General → Login Items"

uninstall:
	@echo "Uninstalling $(APP_NAME)..."
	@rm -f $(INSTALL_DIR)/$(APP_NAME)
	@echo "✅ Uninstalled"
