all: tf target/example.jar

uberjar:
	make target/example.jar

target/example.jar: src/example/*.clj
	lein uberjar

clean:
	cd tf && terraform destroy
	rm target/example.jar

.PHONY: tf
tf: target/example.jar
	cd tf && terraform apply -auto-approve
