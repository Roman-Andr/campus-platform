#!/usr/bin/make

STUDENT_NAME := АндрусевичРД
TYPST := TYPST_FONT_PATHS=fonts typst

# Fixed document date (UNIX time, 2026-11-15 00:00 UTC). Typst writes it into
# the PDF metadata and returns it from datetime.today(), so rebuilding
# unchanged sources yields a byte-identical PDF. Bump it when a new edition
# of the documents is issued.
SOURCE_DATE_EPOCH := 1794700800
export SOURCE_DATE_EPOCH

DOCS := ТЗ РО ПЗ ПМИ ТП ПЗ_Титульный_лист

PDF_DIR := pdf
PDFS := $(foreach doc,$(DOCS),$(PDF_DIR)/$(doc)_$(STUDENT_NAME).pdf)
SHARED_SOURCES := $(wildcard *.typ fonts/* images/*) Makefile

.PHONY: all compile clean help

all: compile

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  compile  - Compile PDFs whose sources changed (default)"
	@echo "  clean    - Remove all compiled PDFs"
	@echo "  help     - Show this help message"

compile: $(PDFS)
	@echo "All PDFs are up to date"

# Each PDF depends only on its own document directory and shared sources.
.SECONDEXPANSION:
$(PDFS): $(PDF_DIR)/%_$(STUDENT_NAME).pdf: \
		$$(wildcard $$*/*.typ $$*/sections/*.typ) $(SHARED_SOURCES) | $(PDF_DIR)
	$(TYPST) compile --root . $*/main.typ $@

$(PDF_DIR):
	mkdir -p $@

clean:
	rm -f $(PDF_DIR)/*.pdf
