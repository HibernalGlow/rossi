"""同步门禁不能遗漏重写模块，也不能把 pin 提升当成已经完成语义复核。"""
import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
import unittest

from mimage_reuse_inventory import audit_inventory


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.roots = ["rust/local_core/src", "rust/gpu_present/src", "rust/ocr_core/src", "rust/src"]
        for root in self.roots:
            (self.repo / root).mkdir(parents=True, exist_ok=True)
        (self.repo / self.roots[0] / "core.rs").write_text("fn core() {}")
        self.entry = dict(id="rewrite", classification="compatibility_rewrite", local=[self.roots[0]],
            upstream=["src/canonical_image_loader.rs"], repository="mimageviewer", reviewed_at="a"*40,
            reason="different decoding boundary", owner="decoder maintainer", tests=["decoder tests"],
            parity_gaps=["EXIF/ICC"], parity="not proven", action="extract shared policy")
        self.inventory = dict(rust_roots=self.roots, entries=[self.entry])

    def check(self, git=lambda *args: "", ports=None):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            dirty = audit_inventory(self.repo, self.inventory, ports or [], "b"*40, git)
        return dirty, output.getvalue()

    def test_upstream_change_outside_ports_requires_review(self):
        def git(*args):
            return "src/canonical_image_loader.rs\n" if args[0] == "diff" else ""
        dirty, output = self.check(git)
        self.assertTrue(dirty)
        self.assertIn("decoder maintainer", output)
        self.assertIn("EXIF/ICC", output)

    def test_new_rust_module_requires_inventory_entry(self):
        (self.repo / self.roots[1] / "new_gpu.rs").write_text("fn new() {}")
        dirty, output = self.check()
        self.assertTrue(dirty)
        self.assertIn("new_gpu.rs", output)

    def test_deleted_upstream_source_fails_gate(self):
        def git(*args):
            if args[0] == "cat-file" and args[-1].startswith("b"*40+":"):
                raise RuntimeError("upstream source renamed")
            return ""
        self.assertTrue(self.check(git)[0])

    def test_uncommitted_vendor_source_change_fails_gate(self):
        def git(*args):
            if args[0] == "diff" and args[2] == "b"*40:
                return "src/canonical_image_loader.rs\n"
            return ""
        dirty, output = self.check(git)
        self.assertTrue(dirty)
        self.assertIn("vendor 工作树", output)

    def test_invalid_or_nonancestor_review_pin_fails_gate(self):
        self.entry["reviewed_at"] = "not-a-commit"
        self.assertTrue(self.check()[0])
        self.entry["reviewed_at"] = "a"*40
        def git(*args):
            if args[0] == "merge-base":
                raise RuntimeError("pin is not ancestor")
            return ""
        self.assertTrue(self.check(git)[0])

    def test_duplicate_id_and_missing_source_roots_fail_gate(self):
        self.inventory["entries"].append(copy.deepcopy(self.entry))
        self.assertTrue(self.check()[0])
        self.inventory["entries"].pop()
        self.inventory["rust_roots"].pop()
        self.assertTrue(self.check()[0])

    def test_port_cannot_hide_under_an_unrelated_mapping(self):
        ports = [dict(local=self.roots[0]+"/core.rs", upstream="src/other.rs")]
        self.assertTrue(self.check(ports=ports)[0])

    def test_unchanged_complete_inventory_passes(self):
        self.assertFalse(self.check()[0])

    def test_real_inventory_and_all_current_bindings_pass(self):
        import sync_vendored_modules as sync
        inventory = json.loads((sync.REPO / "docs/mimageviewer-reuse-inventory.json").read_text())
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertFalse(audit_inventory(sync.REPO, inventory, sync.PORTS,
                sync.git("rev-parse", "HEAD").strip(), sync.git))


if __name__ == "__main__":
    unittest.main()
