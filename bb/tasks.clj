#!/usr/bin/env bb
;;; tasks.clj — babashka runner for :CMD: blocks in org files.
;;;
;;; bb orchestrates, it does not evaluate types (that is the sidecar's job).
;;; A command block looks like:
;;;   :CMD: build-house
;;;   :RUN: echo "2 5 Bahnhof 12"
;;;   :EXPECT: 2 5 Bahnhof 12
;;;   :DEPS: streetname        ; optional, other :CMD: names
;;; Commands run in dependency order (a DAG — no cycles allowed), and each
;;; command's stdout must equal EXPECT. That is the whole contract.
;;;
;;; Usage: bb tasks.clj notes/commands.org

(ns tasks
  (:require [babashka.process :as p]
            [clojure.string :as str]))

(defn parse-commands
  "Pull :CMD:/:RUN:/:EXPECT:/:DEPS: blocks out of an org file as data."
  [path]
  (let [text (slurp path)
        blocks (re-seq #"(?ms)^:CMD:\s*(\S+).*?:RUN:\s*(.+?)\s*$\n(?:.*?:EXPECT:\s*(.+?)\s*$\n)?(?:.*?:DEPS:\s*(.+?)\s*$\n)?" text)]
    (mapv (fn [[_ name run expect deps]]
            {:name name
             :run run
             :expect (or expect "")
             :deps (if deps (str/split (str/trim deps) #"\s+") [])})
          blocks)))

(defn topo-order
  "Dependency order; throws on a cycle (circular reasoning is not a pipeline)."
  [cmds]
  (let [by-name (into {} (map (juxt :name identity) cmds)]
    (loop [remaining cmds, order [], seen #{}]
      (if (empty? remaining)
        order
        (let [ready (filter (fn [{:keys [deps]}]
                              (every? seen (map #(if (by-name %) % "") deps))
                            remaining)]
          (when (empty? ready)
            (throw (ex-info "dependency cycle in commands" {:remaining (mapv :name remaining)})))
          (recur (remove (set (map :name ready)) remaining)
                 (concat order ready)
                 (into seen (map :name ready))))))))

(defn run-command [{:keys [name run expect]}]
  (let [{:keys [out exit]} (p/sh ["bash" "-c" run])
        out (str/trim out)
        ok? (and (zero? exit) (= out (str/trim expect)))]
    (println (if ok? "PASS" "FAIL") name
             (when-not ok? (str "\n  expected: " expect "\n  got:      " out)))
    ok?))

(defn -main [& args]
  (let [path (or (first args) "notes/commands.org")
        cmds (topo-order (parse-commands path))
        results (mapv run-command cmds)]
    (System/exit (if (every? true? results) 0 1))))

(apply -main *command-line-args*)
