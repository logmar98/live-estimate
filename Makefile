all: install

install:
	chmod +x exten2.sh exten.sh setup_hourscounter.sh update_live_estimate_ext.sh
	@echo "Installing live-estimate counter CLI & services..."
	./setup_hourscounter.sh
	@echo "Deploying optimized 42 Live-Estimate Brave Extension..."
	./update_live_estimate_ext.sh

update-ext:
	chmod +x update_live_estimate_ext.sh
	./update_live_estimate_ext.sh
