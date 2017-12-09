(defproject example "0.0.1-SNAPSHOT"
  :dependencies [[org.clojure/clojure "1.8.0"]
                 [uswitch/lambada "0.1.2"]
                 [cheshire "5.7.1"]]
  :main example.core
  :description "A sample API, using Clojure and Lambda"
  :target-path "target/"
  :uberjar-name "example.jar"
  :profiles {:uberjar {:aot :all}})
