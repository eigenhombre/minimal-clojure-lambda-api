(ns example.core
  (:require [cheshire.core :as json]
            [clojure.java.io :refer [reader writer]]
            [uswitch.lambada.core :refer [deflambdafn]]))


(defn handle-event [event]
  (println "Your lambda is ready, madame.")  ;; <--should go to CloudWatch logs
  {"isBase64Encoded" false
   "statusCode" 200
   "headers" {}
   "body" (json/generate-string {:status "OK"
                                 :extra-stuff "I am lambda, hear me roar"})})


(deflambdafn example.core.LambdaFunction [is os ctx]
  (let [event (json/parse-stream (reader is))
        res (handle-event event)]
    (with-open [w (writer os)]
      (json/generate-stream res w))))
