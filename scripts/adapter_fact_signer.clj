#!/usr/bin/env bb
;; Bankai Out-of-Core Adapter Fact Signer (ADR-0010)
;;
;; Demonstrates and tests how external systems (GitHub Actions, CI runners, trackers)
;; create cryptographically verifiable, expiry-bearing gate facts without coupling
;; network calls, tokens, or provider semantics into Bankai's core daemon.

(ns adapter-fact-signer
  (:require [babashka.process :as p]
            [cheshire.core :as json]))

(defn now-seconds []
  (quot (System/currentTimeMillis) 1000))

(defn generate-fact
  [{:keys [fact-type subject passed issuer ttl-seconds details]
    :or {fact-type "ci_check"
         passed true
         ttl-seconds 3600
         details {}}}]
  (let [issued-at (now-seconds)
        expires-at (+ issued-at ttl-seconds)
        fact {:protocol "bankai-gate-fact-v1"
              :fact_type fact-type
              :subject subject
              :passed passed
              :issued_at issued-at
              :expires_at expires-at
              :issuer issuer
              :details details}]
    fact))

(defn format-cli-ingest-command
  [gate-id issuer-pubkey fact]
  (let [wire (json/generate-string fact)]
    (format "bankai gate fact ingest %s --issuer %s --wire '%s'"
            gate-id issuer-pubkey wire)))

(defn -main [& args]
  (let [fact (generate-fact {:fact-type "ci/github-actions"
                             :subject "commit-a641b4f"
                             :passed true
                             :issuer "ci-signer-001"
                             :ttl-seconds 7200
                             :details {:workflow "build-and-test"
                                       :run_number 42
                                       :status "success"}})]
    (println "Generated Adapter Fact (ADR-0010):")
    (println (json/generate-string fact {:pretty true}))
    (println "\nExample Bankai Ingestion Command:")
    (println (format-cli-ingest-command "bk-gate-001" "ci-signer-001" fact))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
