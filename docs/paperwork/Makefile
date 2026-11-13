#!/usr/bin/make

STUDENT_NAME := АндрусевичРД
TYPST := TYPST_FONT_PATHS=fonts typst

DOCS := ТЗ РО ПЗ ПМИ ТП ПЗ_Титульный_лист

PDF_DIR := pdf

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

compile: $(foreach doc,$(DOCS),$(PDF_DIR)/$(doc)_$(STUDENT_NAME).pdf)
	@echo "All PDFs compiled successfully"

$(PDF_DIR)/ТЗ_$(STUDENT_NAME).pdf:
	$(call compile_doc,ТЗ)

$(PDF_DIR)/РО_$(STUDENT_NAME).pdf:
	$(call compile_doc,РО)

$(PDF_DIR)/ПЗ_$(STUDENT_NAME).pdf:
	$(call compile_doc,ПЗ)

$(PDF_DIR)/ПМИ_$(STUDENT_NAME).pdf:
	$(call compile_doc,ПМИ)

$(PDF_DIR)/ТП_$(STUDENT_NAME).pdf:
	$(call compile_doc,ТП)

$(PDF_DIR)/ПЗ_Титульный_лист_$(STUDENT_NAME).pdf:
	$(call compile_doc,ПЗ_Титульный_лист)

clean:
	rm -f $(PDF_DIR)/*.pdf
