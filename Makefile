EXT_DIR := $(HOME)/.local/share/live-estimate-brave-ext

.PHONY: all install update-ext

all: install

install:
	@chmod +x exten2.sh exten.sh setup_hourscounter.sh update_live_estimate_ext.sh
	@log=$$(mktemp); \
	if ! ./setup_hourscounter.sh >"$$log" 2>&1 || ! ./update_live_estimate_ext.sh >>"$$log" 2>&1; then \
		cat "$$log" >&2; \
		rm -f "$$log"; \
		exit 1; \
	fi; \
	rm -f "$$log"
	@echo "Add extension in Brave (first time):"
	@echo "  1. Open brave://extensions"
	@echo "  2. Enable \"Developer mode\" (top-right)"
	@echo "  3. Click \"Load unpacked\" and select: $(EXT_DIR)"
	@echo ""
	@echo "Update extension in Brave (already added):"
	@echo "  1. Open brave://extensions"
	@echo "  2. Click the reload icon (↻) on \"42 Live-Estimate Counter\""

update-ext:
	@chmod +x update_live_estimate_ext.sh
	@./update_live_estimate_ext.sh
