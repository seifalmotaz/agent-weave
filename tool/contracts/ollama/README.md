# Ollama upstream snapshots

`openapi.yaml` and `types.go` are unmodified from ollama/ollama revision
`e9fde36d75fea66579d84099956ce1430792737a` (MIT; see LICENSE).
`openapi.json` is the JSON parse of the YAML, used for offline checks without a
Python YAML dependency. To regenerate it after reviewing a new source revision:

```sh
ruby -rpsych -rjson -e 'puts JSON.generate(Psych.safe_load(File.read(ARGV[0]), [], [], true))' tool/contracts/ollama/openapi.yaml > tool/contracts/ollama/openapi.json
```

Update source hashes and revision in `tool/ollama_contract.py`, review the Go
supplement and field dispositions, regenerate documentation, and run its tests.
