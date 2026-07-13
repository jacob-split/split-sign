#!/usr/bin/env python3
"""Restore the legacy Split funding masters used by portal automation.

This script is intentionally host-side.  It seeds the historical template IDs
94 (Payroc Letter of Direction) and 95 (FRPA), attaches clean source PDFs, and
recreates the semantic fields consumed by MerchantPortalReviewAgreementGenerator.

Run on the Split Signature host, where the DocuSeal container and API token are
available.  Existing populated masters are left untouched unless --force is
provided.
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import uuid
from pathlib import Path


ROLE = "Merchant"
DEFAULT_API_BASE = "http://127.0.0.1:3000"
DEFAULT_TOKEN_PATH = "/home/ubuntu/.split-sign-api-token"
DEFAULT_CONTAINER = "docuseal-app-1"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--frpa-pdf", required=True, type=Path)
    parser.add_argument("--lod-pdf", required=True, type=Path)
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--token-path", type=Path, default=Path(DEFAULT_TOKEN_PATH))
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def api(token: str, api_base: str, method: str, path: str, body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        f"{api_base}{path}",
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "X-Auth-Token": token,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            raw = response.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} failed: HTTP {exc.code}: {detail}") from exc


def maybe_get_template(token: str, api_base: str, template_id: int) -> dict | None:
    try:
        return api(token, api_base, "GET", f"/api/templates/{template_id}")
    except RuntimeError as exc:
        if "HTTP 404" in str(exc):
            return None
        raise


def seed_template_record(container: str, template_id: int, name: str) -> None:
    ruby = f"""
account = Account.order(:id).first || raise('No DocuSeal account found')
author = User.find_by(email: 'jacob@split-llc.com') || User.order(:id).first || raise('No DocuSeal user found')
folder = TemplateFolders.find_or_create_by_name(author, 'Portal Agreements')
template = Template.unscoped.find_by(id: {template_id})
unless template
  template = Template.create!(
    id: {template_id}, account: account, author: author, folder: folder,
    name: {name!r}, source: :api, external_id: 'restored_funding_master:{template_id}'
  )
end
template.update!(archived_at: nil, name: {name!r}, folder: folder)
ActiveRecord::Base.connection.execute(
  "SELECT setval(pg_get_serial_sequence('templates','id'), GREATEST((SELECT MAX(id) FROM templates), 1), true)"
)
puts template.id
"""
    subprocess.run(
        [
            "sudo",
            "docker",
            "exec",
            "-w",
            "/app",
            container,
            "/app/bin/bundle",
            "exec",
            "rails",
            "runner",
            ruby,
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def area(page: int, x: float, y: float, w: float, h: float, attachment_uuid: str) -> dict:
    return {
        "page": page,
        "x": round(x, 4),
        "y": round(y, 4),
        "w": round(w, 4),
        "h": round(h, 4),
        "attachment_uuid": attachment_uuid,
    }


def field(
    submitter_uuid: str,
    attachment_uuid: str,
    name: str,
    field_type: str,
    areas: list[tuple[int, float, float, float, float]],
    *,
    default: str | bool | None = None,
    font_size: int = 8,
) -> dict:
    interactive = field_type in {"signature", "initials"}
    preferences = {"color": "black"}
    if field_type not in {"signature", "initials", "checkbox"}:
        preferences.update({"font": "Helvetica", "font_size": font_size, "align": "left", "valign": "center"})
    item = {
        "uuid": str(uuid.uuid4()),
        "submitter_uuid": submitter_uuid,
        "name": name,
        "type": field_type,
        "required": interactive,
        "readonly": not interactive,
        "preferences": preferences,
        "areas": [area(*coords, attachment_uuid) for coords in areas],
    }
    if default is not None:
        item["default_value"] = default
    return item


def frpa_fields(submitter_uuid: str, attachment_uuid: str) -> list[dict]:
    text = lambda name, areas, **kw: field(submitter_uuid, attachment_uuid, name, "text", areas, **kw)
    signature = lambda name, areas: field(submitter_uuid, attachment_uuid, name, "signature", areas)
    checkbox = lambda name, areas, **kw: field(submitter_uuid, attachment_uuid, name, "checkbox", areas, **kw)

    return [
        text("Legal Name", [(0, 0.075, 0.100, 0.25, 0.016)]),
        text("DBA Name", [(0, 0.405, 0.100, 0.24, 0.016)]),
        text("Entity and State", [(0, 0.670, 0.100, 0.25, 0.016)]),
        text("Business Address", [(0, 0.075, 0.132, 0.27, 0.016), (0, 0.075, 0.169, 0.27, 0.016)]),
        text("City", [(0, 0.370, 0.132, 0.12, 0.016), (0, 0.370, 0.169, 0.12, 0.016)]),
        text("State", [(0, 0.490, 0.132, 0.06, 0.016), (0, 0.490, 0.169, 0.06, 0.016)]),
        text("Business Zip", [(0, 0.660, 0.132, 0.12, 0.016), (0, 0.660, 0.169, 0.12, 0.016)]),
        text(
            "Owner Full Name",
            [
                (0, 0.075, 0.207, 0.25, 0.016),
                (0, 0.080, 0.918, 0.18, 0.016),
                (9, 0.155, 0.492, 0.20, 0.016),
                (12, 0.130, 0.653, 0.25, 0.016),
                (13, 0.070, 0.013, 0.26, 0.016),
                (13, 0.160, 0.341, 0.28, 0.016),
                (14, 0.100, 0.084, 0.40, 0.016),
                (14, 0.075, 0.708, 0.24, 0.016),
            ],
        ),
        text("Title", [(0, 0.370, 0.207, 0.20, 0.016), (0, 0.515, 0.853, 0.18, 0.016), (12, 0.130, 0.673, 0.25, 0.016), (14, 0.130, 0.615, 0.20, 0.016)]),
        text("Business Phone", [(0, 0.660, 0.207, 0.25, 0.016), (13, 0.170, 0.499, 0.30, 0.016)]),
        text("Owner Phone", [(13, 0.160, 0.530, 0.30, 0.016)]),
        text("Bank Name", [(0, 0.300, 0.247, 0.18, 0.016), (1, 0.330, 0.821, 0.25, 0.016), (12, 0.165, 0.453, 0.30, 0.016)]),
        text("Routing Number", [(0, 0.670, 0.247, 0.16, 0.016), (1, 0.360, 0.769, 0.18, 0.016), (12, 0.155, 0.540, 0.22, 0.016)]),
        text("Account Number", [(0, 0.865, 0.247, 0.075, 0.016), (1, 0.360, 0.743, 0.18, 0.016), (12, 0.580, 0.540, 0.22, 0.016)], font_size=6),
        text("Account Name", [(1, 0.350, 0.800, 0.28, 0.016)]),
        text("Purchase Price", [(0, 0.200, 0.287, 0.14, 0.016), (0, 0.490, 0.426, 0.10, 0.016)]),
        text("Initial Periodic Amount", [(0, 0.640, 0.287, 0.15, 0.016)]),
        text("Purchased Amount", [(0, 0.200, 0.326, 0.14, 0.016)]),
        text("Specified Percentage", [(0, 0.200, 0.363, 0.10, 0.016)]),
        checkbox("Daily Frequency", [(0, 0.161, 0.411, 0.015, 0.015)], default=True),
        text("Prior Balance", [(0, 0.490, 0.443, 0.10, 0.016)], default="0.00"),
        text("ACH Program Fee", [(0, 0.490, 0.459, 0.10, 0.016)], default="0.00"),
        text("Origination Fee", [(0, 0.490, 0.476, 0.10, 0.016)]),
        text("Net Amount Funded", [(0, 0.490, 0.486, 0.10, 0.016)], font_size=7),
        text("Factor Rate", [(0, 0.690, 0.426, 0.19, 0.018)], font_size=7),
        text(
            "Legal Business Name",
            [
                (0, 0.150, 0.830, 0.35, 0.017),
                (1, 0.350, 0.800, 0.28, 0.016),
                (12, 0.165, 0.600, 0.27, 0.016),
                (13, 0.290, 0.034, 0.28, 0.016),
                (13, 0.200, 0.404, 0.35, 0.016),
                (14, 0.240, 0.073, 0.30, 0.016),
            ],
        ),
        text("EIN / Tax ID", [(12, 0.730, 0.600, 0.20, 0.016)]),
        text("DBA Name", [(13, 0.245, 0.061, 0.28, 0.016), (13, 0.210, 0.436, 0.35, 0.016)]),
        text("Business Address Full", [(13, 0.160, 0.467, 0.65, 0.016), (14, 0.360, 0.310, 0.45, 0.016)], font_size=7),
        text("Business Email", [(14, 0.510, 0.294, 0.37, 0.016)], font_size=7),
        text("Home Address", [(14, 0.360, 0.386, 0.45, 0.016)], font_size=7),
        text("Owner Email", [(14, 0.510, 0.371, 0.38, 0.016)], font_size=7),
        text("Agreement Date", [(12, 0.130, 0.703, 0.20, 0.016), (13, 0.150, 0.562, 0.20, 0.016), (14, 0.080, 0.101, 0.20, 0.016), (14, 0.365, 0.583, 0.18, 0.016), (14, 0.365, 0.708, 0.18, 0.016)]),
        text("Merchant Signer Name", [(14, 0.075, 0.583, 0.24, 0.016)]),
        signature("Merchant Signature", [(0, 0.285, 0.837, 0.19, 0.030)]),
        signature("Guarantor Signature - Agreement", [(0, 0.405, 0.909, 0.19, 0.030)]),
        signature("Guarantor Signature - Guaranty", [(9, 0.490, 0.478, 0.19, 0.030)]),
        signature("Merchant Signature - ACH", [(12, 0.240, 0.610, 0.22, 0.035)]),
        signature("Merchant Signature - Release", [(13, 0.270, 0.366, 0.23, 0.035)]),
        signature("Guarantor Signature - Service Waiver", [(14, 0.185, 0.741, 0.22, 0.035)]),
    ]


def lod_fields(submitter_uuid: str, attachment_uuid: str) -> list[dict]:
    text = lambda name, areas, **kw: field(submitter_uuid, attachment_uuid, name, "text", areas, **kw)
    signature = lambda name, areas: field(submitter_uuid, attachment_uuid, name, "signature", areas)
    return [
        text("Agreement Date", [(0, 0.120, 0.105, 0.20, 0.018)]),
        text(
            "Legal Business Name",
            [(0, 0.235, 0.226, 0.20, 0.019), (0, 0.383, 0.299, 0.23, 0.016), (0, 0.530, 0.825, 0.32, 0.018)],
            font_size=7,
        ),
        text("Funding Agreement Type", [(0, 0.133, 0.316, 0.12, 0.016), (0, 0.240, 0.386, 0.16, 0.016), (0, 0.494, 0.456, 0.16, 0.016)], default="FRPA", font_size=7),
        text("Funding Company", [(0, 0.383, 0.316, 0.14, 0.016)], default="Split LLC", font_size=7),
        text("Specified Percentage", [(0, 0.773, 0.334, 0.05, 0.016), (0, 0.258, 0.403, 0.05, 0.016)]),
        text("Title", [(0, 0.595, 0.892, 0.20, 0.016)]),
        signature("Merchant Signature - Letter of Direction", [(0, 0.580, 0.865, 0.22, 0.035)]),
    ]


def restore_one(
    *,
    token: str,
    api_base: str,
    container: str,
    template_id: int,
    name: str,
    pdf_path: Path,
    fields_builder,
    force: bool,
) -> dict:
    existing = maybe_get_template(token, api_base, template_id)
    if existing is None:
        seed_template_record(container, template_id, name)
        existing = maybe_get_template(token, api_base, template_id)
    if existing is None:
        raise RuntimeError(f"Template {template_id} could not be seeded")

    if existing.get("schema") and existing.get("fields") and not force:
        return {"id": template_id, "name": name, "status": "already_present", "field_count": len(existing["fields"])}

    # Production's retained API token is intentionally read-only for template
    # mutation.  Perform the privileged master restore inside the Rails runtime,
    # then use the API only for readback verification.
    placeholder_submitter = "__SUBMITTER_UUID__"
    placeholder_attachment = "__ATTACHMENT_UUID__"
    fields = fields_builder(placeholder_submitter, placeholder_attachment)
    spec = {
        "template_id": template_id,
        "name": name,
        "role": ROLE,
        "force": force,
        "pdf_filename": pdf_path.name,
        "fields": fields,
    }
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
        json.dump(spec, handle)
        spec_path = Path(handle.name)
    container_pdf = f"/tmp/{template_id}-{pdf_path.name}"
    container_spec = f"/tmp/{template_id}-funding-master.json"
    try:
        subprocess.run(["sudo", "docker", "cp", str(pdf_path), f"{container}:{container_pdf}"], check=True)
        subprocess.run(["sudo", "docker", "cp", str(spec_path), f"{container}:{container_spec}"], check=True)
        subprocess.run(
            ["sudo", "docker", "exec", container, "chmod", "0644", container_pdf, container_spec],
            check=True,
        )
        ruby = f"""
spec = JSON.parse(File.read({container_spec!r}))
template = Template.unscoped.find(spec.fetch('template_id'))
if template.schema.present? && !spec['force']
  raise "Template #{{template.id}} already has documents; use --force to replace"
end
if spec['force']
  template.documents.each(&:purge)
  template.update!(schema: [], fields: [])
end
source_path = {container_pdf!r}
tempfile = Tempfile.new(['funding-master-', '.pdf'])
tempfile.binmode
tempfile.write(File.binread(source_path))
tempfile.rewind
upload = ActionDispatch::Http::UploadedFile.new(
  tempfile: tempfile, filename: spec.fetch('pdf_filename'), type: 'application/pdf'
)
documents = Array.wrap(
  Templates::CreateAttachments.handle_pdf_or_image(
    template, upload, nil, ActionController::Parameters.new, extract_fields: true
  )
).flatten
raise 'No template document was created' if documents.empty?
submitters = template.submitters.presence || [{{ 'name' => spec.fetch('role'), 'uuid' => SecureRandom.uuid }}]
submitters.first['name'] = spec.fetch('role')
submitters.first['uuid'] ||= SecureRandom.uuid
attachment_uuid = documents.first.uuid
fields = spec.fetch('fields').map do |field|
  field['submitter_uuid'] = submitters.first['uuid'] if field['submitter_uuid'] == '__SUBMITTER_UUID__'
  Array.wrap(field['areas']).each do |field_area|
    field_area['attachment_uuid'] = attachment_uuid if field_area['attachment_uuid'] == '__ATTACHMENT_UUID__'
  end
  field
end
template.update!(
  name: spec.fetch('name'),
  external_id: "restored_funding_master:#{{template.id}}",
  shared_link: false,
  archived_at: nil,
  submitters: submitters,
  schema: documents.map {{ |document| {{ 'attachment_uuid' => document.uuid, 'name' => document.filename.base }} }},
  fields: fields
)
puts({{ id: template.id, fields: template.fields.size, schema: template.schema.size }}.to_json)
"""
        completed = subprocess.run(
            [
                "sudo", "docker", "exec", "-w", "/app", container,
                "/app/bin/bundle", "exec", "rails", "runner", ruby,
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                f"Template {template_id} Rails restore failed: "
                f"{completed.stderr.strip() or completed.stdout.strip()}"
            )
        if not completed.stdout.strip():
            raise RuntimeError(f"Template {template_id} Rails restore returned no verification output")
    finally:
        spec_path.unlink(missing_ok=True)
        subprocess.run(["sudo", "docker", "exec", container, "rm", "-f", container_pdf, container_spec], check=False)

    restored = api(token, api_base, "GET", f"/api/templates/{template_id}")
    return {"id": template_id, "name": name, "status": "restored", "field_count": len(restored.get("fields") or [])}


def main() -> int:
    args = parse_args()
    for path in (args.frpa_pdf, args.lod_pdf, args.token_path):
        if not path.is_file():
            raise FileNotFoundError(path)
    token = args.token_path.read_text(encoding="utf-8").strip()
    if not token:
        raise RuntimeError(f"Empty API token: {args.token_path}")

    results = [
        restore_one(
            token=token,
            api_base=args.api_base,
            container=args.container,
            template_id=95,
            name="FRPA_payroc",
            pdf_path=args.frpa_pdf,
            fields_builder=frpa_fields,
            force=args.force,
        ),
        restore_one(
            token=token,
            api_base=args.api_base,
            container=args.container,
            template_id=94,
            name="LOD_",
            pdf_path=args.lod_pdf,
            fields_builder=lod_fields,
            force=args.force,
        ),
    ]
    print(json.dumps({"ok": True, "templates": results}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # operational script: compact fail-closed output
        print(json.dumps({"ok": False, "error": str(exc)}), file=sys.stderr)
        raise
