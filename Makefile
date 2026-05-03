SHELL := /bin/sh

.PHONY: validate install install-copy reload

validate:
	qmllint DMSSesh.qml DMSSeshSettings.qml

install:
	sh scripts/install-plugin --symlink --reload

install-copy:
	sh scripts/install-plugin --copy --reload

reload:
	dms ipc plugins reload dmsSesh
