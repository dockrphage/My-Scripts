# ---------------------------------------------------------------------------
# Makefile for aws_spot_price.py
# A clean, self-documenting automation layer for running, testing, and
# maintaining the AWS Spot Price fetcher script.
# ---------------------------------------------------------------------------

PYTHON := python3
VENV := .venv
ACTIVATE := $(VENV)/bin/activate

# Default instance type if none is provided
INSTANCE ?= t3.micro

# ---------------------------------------------------------------------------
# Help Menu
# ---------------------------------------------------------------------------

.PHONY: help
help:
    @echo ""
    @echo "AWS Spot Price Fetcher — Makefile Commands"
    @echo "-------------------------------------------"
    @echo "make venv           Create virtual environment"
    @echo "make install        Install dependencies into venv"
    @echo "make run            Run script (default: INSTANCE=$(INSTANCE))"
    @echo "make run INSTANCE=m5.large"
    @echo "make lint           Run flake8 linting"
    @echo "make clean          Remove caches and temporary files"
    @echo "make reset          Remove venv + caches"
    @echo ""

# ---------------------------------------------------------------------------
# Virtual Environment + Dependencies
# ---------------------------------------------------------------------------

$(VENV):
    $(PYTHON) -m venv $(VENV)

.PHONY: venv
venv: $(VENV)
    @echo "Virtual environment created."

.PHONY: install
install: venv
    . $(ACTIVATE) && pip install --upgrade pip
    . $(ACTIVATE) && pip install boto3 tabulate flake8
    @echo "Dependencies installed."

# ---------------------------------------------------------------------------
# Run Script
# ---------------------------------------------------------------------------

.PHONY: run
run:
    . $(ACTIVATE) && $(PYTHON) aws_spot_price.py --instance-type $(INSTANCE)

# ---------------------------------------------------------------------------
# Linting
# ---------------------------------------------------------------------------

.PHONY: lint
lint:
    . $(ACTIVATE) && flake8 aws_spot_price.py

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

.PHONY: clean
clean:
    rm -rf __pycache__ .pytest_cache
    @echo "Temporary files removed."

.PHONY: reset
reset: clean
    rm -rf $(VENV)
    @echo "Environment fully reset."
