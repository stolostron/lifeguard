.PHONY: install-oc-extension
## install the lifegaurd project as an oc extension
install-oc-extension:
	@cp $(PWD)/clusterpools/apply.sh /usr/local/bin/oc-clusterpool_create
	@echo "Added an oc extension for 'oc clusterpool-create'"
	@cp $(PWD)/clusterpools/delete.sh /usr/local/bin/oc-clusterpool_delete
	@echo "Added an oc extension for 'oc clusterpool-delete'"
	@cp $(PWD)/clusterclaims/apply.sh /usr/local/bin/oc-clusterclaim_create
	@echo "Added an oc extension for 'oc clusterclaim-create'"
	@cp $(PWD)/clusterclaims/delete.sh /usr/local/bin/oc-clusterclaim_delete
	@echo "Added an oc extension for 'oc clusterclaim-delete'"
	@cp $(PWD)/clusterclaims/get_credentials.sh /usr/local/bin/oc-clusterclaim_get_credentials
	@echo "Added an oc extension for 'oc clusterclaim-get-credentials'"

.PHONY: uninstall-oc-extension
## Uninstall the lifegaurd project as an oc extension
uninstall-oc-extension:
	@rm /usr/local/bin/oc-clusterpool_create
	@echo "Removed the oc extension for 'oc clusterpool-create'"
	@rm /usr/local/bin/oc-clusterpool_delete
	@echo "Removed the oc extension for 'oc clusterpool-delete'"
	@rm /usr/local/bin/oc-clusterclaim_create
	@echo "Removed the oc extension for 'oc clusterclaim-create'"
	@rm /usr/local/bin/oc-clusterclaim_delete
	@echo "Removed the oc extension for 'oc clusterclaim-delete'"
	@rm /usr/local/bin/oc-clusterclaim_get_credentials
	@echo "Removed the oc extension for 'oc clusterclaim-get-credentials'"

