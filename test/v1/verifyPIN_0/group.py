#!/usr/bin/env python3
"""
categorize_and_dump.py — Read map.out and emit three categories:
  1) SRAM Bank 0 words (128×32), in order bit[31]..bit[0] with 0b... and 0x...
  2) SRAM Bank 1 words (128×32), same format
  3) SoC bits (soc_bits.out):
       - Categorized (ibex submodules, uart, dmi, timer, gpio, soc_reg, other)
       - One compact "map" line per base signal:
           <base_path_with_upper_indices_preserved>[msb,msb-1,...,lsb] : <bits MSB..LSB>
         Scalars print as:
           <base_path> : <0|1>

Input:
  --map    <path>   map.out produced by create_map.py (TSV: idx, signal, val)
Outputs:
  --outdir <dir>    directory to write outputs (defaults to current dir):
                    - bank0_words.out
                    - bank1_words.out
                    - soc_bits.out
"""
import argparse
import re
from pathlib import Path
from typing import Dict, List, Tuple, Optional

# Detect SRAM banks/words/bits
SRAM_RE = re.compile(
    r"i_croc_soc_i_croc_gen_sram_bank\\?\[(\d+)\\?\]\.i_sram_mem_reg\\?\[(\d+)\\?\]\\?\[(\d+)\\?\]",
    re.IGNORECASE,
)

# ---------- Category configuration ----------
# Final output order
_CAT_ORDER = [
    "ibex/load_store",
    "ibex/if",
    "ibex/id",
    "ibex/cs",
    "ibex/csr",
    "uart",
    "dmi",
    "timer",
    "gpio",
    "soc_reg",
    "other",
]

# Broad (non-ibex-specific) regex patterns as a fallback
_COMPILED_FALLBACK = [
    ("uart",   [re.compile(r"uart", re.I)]),
    ("dmi",    [re.compile(r"\bdmi\b|debug[_\-]?module", re.I)]),
    ("timer",  [re.compile(r"timer|mtime|mtimecmp", re.I)]),
    ("gpio",   [re.compile(r"\bgpio\b", re.I)]),
    ("soc_reg",[re.compile(r"soc[_\-]?reg(s)?|top[_\-]?reg(s)?", re.I)]),
]

# ---------- Heuristics for Ibex submodules ----------
# Token-based primary heuristics
_IBEX_TOKEN_RULES = [
    # ("category", required_any_tokens, optional_any_tokens)
    ("ibex/load_store",
        {"ibex"},
        {"lsu", "load_store", "load-store", "loadstore", "load_store_unit",
         "load-store-unit", "u_load_store_unit", "data_mem", "data_mem_if",
         "dmem", "dcache", "data_cache"}),

    ("ibex/if",
        {"ibex"},
        {"u_if_stage", "if_stage", "if", "instr_fetch", "inst_fetch",
         "prefetch", "fetch", "ifu"}),

    ("ibex/id",
        {"ibex"},
        {"u_id_stage", "id_stage", "id", "decode", "decoder"}),

    ("ibex/cs",  # controller / control signals (not CSR file)
        {"ibex"},
        {"controller", "u_controller", "control", "ctrl", "cs"}),

    ("ibex/csr",  # CSR file/registers
        {"ibex"},
        {"cs_registers", "u_cs_registers", "csr", "csr_file", "csr_regs",
         "csr_addr", "csr_rdata", "csr_wdata", "csr_op"}),
]

# Regex fallback for Ibex
_IBEX_REGEX_FALLBACK = [
    ("ibex/load_store", [r"ibex", r"(load[_\-]?(store|unit)|lsu|data[_\-]?mem|d?cache)"]),
    ("ibex/if",         [r"ibex", r"(if(_|[^a-zA-Z]|$)|instr[_\-]?(fetch|prefetch)|prefetch|if_stage)"]),
    ("ibex/id",         [r"ibex", r"(id(_|[^a-zA-Z]|$)|decode|id_stage)"]),
    ("ibex/cs",         [r"ibex", r"(controller|control|cs(_|[^a-zA-Z]|$))"]),
    ("ibex/csr",        [r"ibex", r"\bcsr(s)?\b|cs_registers|csr_(addr|wdata|rdata|op)"]),
]
_COMPILED_IBEX_REGEX_FALLBACK = [
    (name, [re.compile(pat, re.IGNORECASE) for pat in pats])
    for name, pats in _IBEX_REGEX_FALLBACK
]

# ---------- Utilities ----------
def parse_map_line(line: str):
    """
    Parse a TSV row: idx<TAB>signal<TAB>val
    Return (idx:int, signal:str, val:int) or None for comments/blank.
    """
    line = line.rstrip("\r\n")
    if not line or line.startswith("#"):
        return None
    parts = line.split("\t")
    if len(parts) < 3:
        # try whitespace split as fallback
        parts = line.split()
        if len(parts) < 3:
            return None
        idx, signal, val = parts[0], " ".join(parts[1:-1]), parts[-1]
    else:
        idx, signal, val = parts[0], parts[1], parts[2]
    try:
        idx_i = int(idx)
        val_i = int(val)
        if val_i not in (0, 1):
            return None
    except Exception:
        return None
    return (idx_i, signal, val_i)

def strip_tags(sig: str) -> str:
    "Remove trailing ' ( IN ... ) ( OUT ... )' style tags."
    pos = sig.find(" (")
    return sig if pos == -1 else sig[:pos]

def base_strip_last_bit_index(sig_no_tags: str) -> str:
    """
    Remove ONLY the FINAL '[n]' bit index from the path, preserving any earlier indices
    (e.g., keep '...gen_demux[3].reg' but drop the terminal '[2]' from 'reg[2]').
    If there is no trailing bracketed index, returns the string unchanged.
    """
    return re.sub(r"\[(\d+)\](?!.*\[\d+\])", "", sig_no_tags)

def last_bit_index(sig_no_tags: str) -> Optional[int]:
    "Return the last numeric bracket index if present, else None."
    m_all = list(re.finditer(r"\[(\d+)\]", sig_no_tags))
    if not m_all:
        return None
    return int(m_all[-1].group(1))

def _normalize_tokens(path: str) -> List[str]:
    """
    Lowercase, split the hierarchical path into tokens.
    Strip array indices '[]' and punctuation separators.
    """
    p = path.lower()
    p = re.sub(r"\[\d+\]", "", p)  # drop indices
    raw = re.split(r"[./\\:$ ]+", p)
    tokens = []
    for t in raw:
        if not t:
            continue
        tokens.extend(re.split(r"[_\-]+", t))
    return [t for t in tokens if t]

def _has_any(tokens: List[str], keys: set) -> bool:
    return any(k in tokens for k in keys)

def _looks_like_ibex(tokens: List[str]) -> bool:
    ibexish = {"ibex", "u_ibex_core", "ibex_core", "if_stage", "id_stage",
               "cs_registers", "u_cs_registers", "u_controller", "controller",
               "lsu", "load", "store", "csr"}
    return _has_any(tokens, ibexish)

def determine_category(path: str) -> str:
    """
    Determine high-level category for a SoC signal path.
    Priority:
      1) Ibex token rules
      2) Ibex regex fallback
      3) Generic (UART/DMI/TIMER/GPIO/soc_reg) fallback
      4) 'other'
    """
    tokens = _normalize_tokens(path)

    # 1) Ibex token rules (require path to look ibex-ish)
    if _looks_like_ibex(tokens):
        for cat, required_any, optional_any in _IBEX_TOKEN_RULES:
            if _has_any(tokens, required_any) and _has_any(tokens, optional_any):
                return cat

    # 2) Ibex regex fallback
    for name, pats in _COMPILED_IBEX_REGEX_FALLBACK:
        ok = True
        for pat in pats:
            if not pat.search(path):
                ok = False
                break
        if ok:
            return name

    # 3) Generic fallback (non-ibex)
    for name, pats in _COMPILED_FALLBACK:
        if all(p.search(path) for p in pats):
            return name

    return "other"

# ---------- Emitters ----------
def emit_bank_files(outdir: Path, bank_bits: Dict[int, Dict[int, Dict[int, int]]]) -> None:
    for bank in (0, 1):
        outp = outdir / f"bank{bank}_words.out"
        with outp.open("w", encoding="utf-8") as f:
            f.write(f"# SRAM Bank {bank} — 128 words × 32 bits, printed as word[W].bit[31..0]: 0b... : 0x........\n")
            missing = []
            for w in range(128):
                row = bank_bits.get(bank, {}).get(w, {})
                msb_to_lsb = []
                for b in range(31, -1, -1):
                    if b in row:
                        msb_to_lsb.append(row[b])
                    else:
                        msb_to_lsb.append(0)
                        missing.append((bank, w, b))
                # Keep original 0b/0x summary lines for SRAM words
                v = 0
                for bit in msb_to_lsb:
                    v = (v << 1) | (bit & 1)
                bstr = "0b" + "".join(str(b & 1) for b in msb_to_lsb)
                hstr = "0x" + format(v, "08X")
                f.write(f"word[{w}].bit[31..0]: {bstr}:  {hstr}\n")
            if missing:
                f.write(f"# WARNING: {len(missing)} missing bits were filled with 0.\n")

def emit_soc_file(outdir: Path, soc_groups: Dict[str, List[Tuple[int, int, str, int]]]) -> None:
    """
    Write soc_bits.out with the requested categorization and compact per-base map lines.
    For each base:
      <base_path_with_upper_indices_preserved>[msb,msb-1,...,lsb] : <bits MSB..LSB>
    Scalars:
      <base_path> : <0|1>
    """
    # Prepare first-appearance ordering
    group_items = []
    for base, lst in soc_groups.items():
        first_idx = min(r[0] for r in lst)
        group_items.append((first_idx, base, lst))
    group_items.sort(key=lambda x: x[0])

    # Assign each base to a category (use earliest path to decide)
    categorized: Dict[str, List[Tuple[int, str, List[Tuple[int, int, str, int]]]]] = {k: [] for k in _CAT_ORDER}
    for first_idx, base, lst in group_items:
        sample_path = lst[0][2]
        cat = determine_category(sample_path)
        categorized.setdefault(cat, []).append((first_idx, base, lst))

    soc_out = outdir / "soc_bits.out"
    with soc_out.open("w", encoding="utf-8") as f:
        f.write("# SoC bits — compact map per base signal (MSB..LSB)\n")
        f.write("# Format: <base_path>[iN,iN-1,...,i0] : <bits>\n")
        f.write("# Scalars: <base_path> : <0|1>\n")

        for cat in _CAT_ORDER:
            items = categorized.get(cat, [])
            if not items:
                continue
            f.write(f"\n== {cat} ==\n")
            items.sort(key=lambda x: x[0])

            for _, _, lst in items:
                # Construct base path (preserve upper indices; drop final bit index)
                # Use the first path for base-path derivation (all entries share same base)
                sample = lst[0][2]
                base_path = base_strip_last_bit_index(strip_tags(sample))

                # Collect values by final-bit index and note scalars
                by_index: Dict[int, int] = {}
                scalars: List[Tuple[int, int]] = []  # [(idx_order, val)]
                for idx_order, bit_idx, full_sig, val in lst:
                    if bit_idx is None or bit_idx < 0:
                        scalars.append((idx_order, val))
                    else:
                        by_index[bit_idx] = val

                if by_index:
                    # Emit indices MSB..LSB (present indices only, no gap-filling)
                    indices_desc = sorted(by_index.keys(), reverse=True)
                    bits_desc = "".join(str(by_index[i] & 1) for i in indices_desc)
                    # Print one compact line
                    f.write(f"{base_path}[{','.join(str(i) for i in indices_desc)}] : {bits_desc}\n")

                # Emit scalars (if any) as separate compact lines, preserving first appearance order
                if scalars:
                    for _, v in sorted(scalars, key=lambda r: r[0]):
                        f.write(f"{base_path} : {v}\n")

    print(f"Wrote {outdir / 'bank0_words.out'}")
    print(f"Wrote {outdir / 'bank1_words.out'}")
    print(f"Wrote {soc_out}")

# ---------- Main ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True, help="map.out from create_map.py")
    ap.add_argument("--outdir", default=".", help="directory for output files")
    args = ap.parse_args()

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # Read map
    entries = []
    with Path(args.map).open("r", encoding="utf-8") as f:
        for line in f:
            rec = parse_map_line(line)
            if rec is None:
                continue
            entries.append(rec)  # (idx, signal, val)
    if not entries:
        raise SystemExit("ERROR: no entries parsed from map file.")

    # Categorize
    bank_bits: Dict[int, Dict[int, Dict[int, int]]] = {0: {}, 1: {}}
    # soc_groups maps "base path" (upper indices preserved, final bit index stripped) to list of entries
    soc_groups: Dict[str, List[Tuple[int, int, str, int]]] = {}

    for idx, sig, val in entries:
        sig_nt = strip_tags(sig)
        m = SRAM_RE.search(sig_nt)
        if m:
            bank = int(m.group(1))
            word = int(m.group(2))
            bit  = int(m.group(3))
            if bank in (0, 1):
                bank_bits.setdefault(bank, {}).setdefault(word, {})[bit] = val
            else:
                base = base_strip_last_bit_index(sig_nt)
                bit_i = last_bit_index(sig_nt)
                soc_groups.setdefault(base, []).append((idx, bit_i if bit_i is not None else -1, sig_nt, val))
        else:
            base = base_strip_last_bit_index(sig_nt)
            bit_i = last_bit_index(sig_nt)
            soc_groups.setdefault(base, []).append((idx, bit_i if bit_i is not None else -1, sig_nt, val))

    # Emit outputs
    emit_bank_files(outdir, bank_bits)
    emit_soc_file(outdir, soc_groups)

if __name__ == "__main__":
    main()

