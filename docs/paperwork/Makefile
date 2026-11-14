#!/usr/bin/make

STUDENT_NAME := АндрусевичРД
TYPST := TYPST_FONT_PATHS=fonts typst

DOCS := ТЗ РО ПЗ ПМИ ТП ПЗ_Титульный_лист

PDF_DIR := pdf
PDFS := $(foreach doc,$(DOCS),$(PDF_DIR)/$(doc)_$(STUDENT_NAME).pdf)
SOURCES := $(wildcard *.typ */*.typ */sections/*.typ fonts/* images/*)

define compile_doc
	$(TYPST) compile --root . $(1)/main.typ $(PDF_DIR)/$(1)_$(STUDENT_NAME).pdf
endef

.PHONY: all compile clean help

all: clean compile

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  compile  - Compile all PDFs"
	@echo "  clean   - Remove all compiled PDFs"
	@echo "  help    - Show this help message"

compile: $(PDFS)
	@echo "All PDFs compiled successfully"

$(PDFS): $(PDF_DIR)/%_$(STUDENT_NAME).pdf: $(SOURCES) Makefile | $(PDF_DIR)
	$(call compile_doc,$*)

$(PDF_DIR):
	mkdir -p $@

clean:
	rm -f $(PDF_DIR)/*.pdf
