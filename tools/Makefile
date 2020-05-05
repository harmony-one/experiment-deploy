PUBBUCKET:=s3://haochen-harmony-pub/pub

systemd_release: harmony.service.template enable-systemd-service.sh
	aws s3 cp enable-systemd-service.sh $(PUBBUCKET)/systemd/install.sh --acl public-read
	aws s3 cp harmony.service.template $(PUBBUCKET)/systemd/harmony.service.template --acl public-read

exporter_release: install-node_exporter.sh
	aws s3 cp install-node_exporter.sh $(PUBBUCKET)/node_exporter/install.sh --acl public-read

snapshot_release: install-db-snapshot.sh
	aws s3 cp install-db-snapshot.sh $(PUBBUCKET)/db_snapshot/install.sh --acl public-read
	aws s3 cp mainnet.snapshot.json $(PUBBUCKET)/db_snapshot/default.json --acl public-read
	aws s3 cp test.only.json $(PUBBUCKET)/db_snapshot/test.only.json --acl public-read

PHONY: systemd_release exporter_release snapshot_release
