comma:= ,
empty:=
space:= $(empty) $(empty)

SOLC=solc

SOLC_REMAPPINGS =utils=utils
SOLC_REMAPPINGS+=platform=platform
SOLC_OUTPUTS =abi
SOLC_OUTPUTS+=bin
SOLC_OUTPUTS+=bin-runtime
# These output formats are not useful
#SOLC_OUTPUTS+=hashes
#SOLC_OUTPUTS+=metadata
SOLC_OUTPUT_FORMAT=--combined-json $(subst $(space),$(comma),$(SOLC_OUTPUTS))

SOLC_FLAGS=$(SOLC_REMAPPINGS) $(SOLC_OUTPUT_FORMAT)

SOLC_TARGETS =$(shell echo campaigns/*.sol)
SOLC_TARGETS+=$(shell echo ico/*.sol)
contracts.json: $(SOLC_TARGETS)
	$(SOLC) $(SOLC_FLAGS) $^ > $@

contracts.min.json: contracts.json | $(SOLC_TARGETS)
	python -c "import sys; \
		   files = sys.argv[1:]; \
		   import json; \
		   f = open('$<', 'r'); \
		   contracts = json.loads(f.read()); \
		   f.close(); \
		   contracts = { \
		   	'contracts': dict((k, v) \
		   		for k, v in contracts['contracts'].items() \
				if k.split(':')[0] in files) \
		   }; \
		   print(json.dumps(contracts))" $| > $@

.PHONY: clean
clean:
	-rm -f contracts.json
	-rm -f contracts.min.json
