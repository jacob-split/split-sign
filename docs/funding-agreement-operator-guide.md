# Funding agreement operator guide

## Jacob's operating defaults (confirmed October 8, 2026)

Purchase Price Paid to Merchant is the funded purchase price. Purchased Amount
of Future Receipts equals that purchase price multiplied by the deal's factor
rate. The factor rate and the Specified Percentage are different inputs.
Specified Percentage and holdback are synonymous: the percentage of receipts
remitted. Never interpret the factor rate as the holdback or copy an old deal's
factor or percentage into a new agreement.

Default periodic frequency is daily, Monday through Friday. Preserve an
operator's existing checked frequency and variable-payment selections. Do not
reset manually edited fields by regenerating from a master template.

The optional daily ACH program is off unless Jacob explicitly requests it.
Preserve signatures or program fields he has removed. A separate contingent
ACH authorization in the agreement is not the optional daily ACH program;
do not remove or restore it by inference.

For the initial periodic amount, Jacob's instructed calculation is total
purchased receipts divided by 90, rounded to whole cents. This divisor is not
a fixed contract term, a promise of 90 payments, or a verified sales forecast.
Use the same amount wherever the agreement and applicable disclosure request
it. Confirm any transaction-specific override rather than replacing it with a
master-template example.

## State-specific disclosures

Inspect the merchant's verified location and the actual PDF headings before
filling disclosures, especially Utah, New York, Virginia and Connecticut.
Complete every applicable continuation page, not merely the first page.
Connecticut has two logical disclosure-form pages; in the current source, its
first form page overflows, so the two logical pages occupy three PDF pages.
Other state-specific requirements and the existing FL/CA checks still apply.

For source PDF SHA-256
`7da43afb720949e5b033ed702decab36790d8e971a4ef4c255b2289e567f9a52`,
verified physical page numbers (one-based) are Utah/Florida 16, New York/
California 17-18, Virginia 19-20, and Connecticut 21-23. The legacy JSON layout
map is not reliable for indexing these disclosures. Recheck headings, page
count and hash whenever the source changes; do not blindly reuse offsets.

Virginia Code section 6.2-2231(4) calls for an estimated number of payments
based on projected sales volume. A variable schedule alone does not establish
that this item is inapplicable. Jacob's October 8 request for N/A on the East
Coast Edge draft is a deal-specific draft instruction, not a general compliance
default. Flag the discrepancy for review rather than inventing a sales
projection or substituting the 90 divisor as a forecast.

10VAC5-240-30 permits N/A for genuinely inapplicable information and requires
both pages to be signed and dated when continuation information is used.
Populate verified business data and approved economics; leave actual signatures
and signer dates to the recipient. Check that recipient and provider details,
all potential fees, broker compensation and prepayment policy are supported by
records or explicit instructions. No referral record is not proof that broker
compensation is zero.

Official references checked October 8, 2026:
- https://law.lis.virginia.gov/vacode/title6.2/chapter22.1/section6.2-2231/
- https://law.lis.virginia.gov/admincode/title10/agency5/chapter240/section30/

## Editing and verification

Read the live template first and preserve user changes and existing agreement
history. Modify the existing unsigned draft, not a replacement. Snapshot before
changes, compare after, render the affected pages and inspect their placement.
Keep duplicated amounts consistent and remove obsolete ambiguity notes only
when their replacements are confirmed.

Draft preparation does not authorize sending, signing, submitting, disbursing
funds, enabling sharing or deployment. Keep all those actions separate. An
unresolved disclosure item must not be represented as ready for delivery.
Do not bypass the automated funding packet's state-disclosure guard or alter
master forms merely to make a particular draft pass.
