#!/usr/bin/env python3
"""Volume Studio – Staff User Guide PDF."""

import os
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.platypus import (
    Paragraph, Spacer, Table, TableStyle,
    HRFlowable, PageBreak, NextPageTemplate,
    BaseDocTemplate, Frame, PageTemplate
)

# ── Brand palette ──────────────────────────────────────────────────────────────
VS_SLATE      = colors.HexColor("#506070")
VS_SLATE_DARK = colors.HexColor("#374B5A")
VS_SLATE_LIGHT= colors.HexColor("#E8EEF3")
VS_CREAM      = colors.HexColor("#F5EDE0")
VS_DARK       = colors.HexColor("#1A1A1A")
VS_MID        = colors.HexColor("#4A5568")
VS_LIGHT      = colors.HexColor("#8A9BAE")
VS_BORDER     = colors.HexColor("#C8D4DC")
GREEN         = colors.HexColor("#16A34A")
AMBER         = colors.HexColor("#B45309")
RED_C         = colors.HexColor("#DC2626")
WHITE         = colors.white

W, H   = A4          # 595.3 x 841.9 pt
MARGIN = 18 * mm
CW     = W - 2 * MARGIN

LOGO_SLATE = "priv/static/images/volume-studio-logos/logo/PNG/LOGO1-1.png"
LOGO_BLACK = "priv/static/images/volume-studio-logos/logo/PNG/LOGO1-2.png"
ICON_SLATE = "priv/static/images/volume-studio-logos/icon/PNG/ISOTIPO-1.png"
ICON_BLACK = "priv/static/images/volume-studio-logos/icon/PNG/ISOTIPO-2.png"

# ── Styles ─────────────────────────────────────────────────────────────────────
def sty(name, **kw):
    return ParagraphStyle(name, **kw)

H1   = sty("H1",  fontName="Helvetica-Bold", fontSize=16, textColor=VS_DARK,
            leading=22, spaceBefore=14, spaceAfter=4)
H2   = sty("H2",  fontName="Helvetica-Bold", fontSize=11, textColor=VS_SLATE,
            leading=16, spaceBefore=12, spaceAfter=3)
BODY = sty("BD",  fontName="Helvetica",      fontSize=10, textColor=VS_MID,
            leading=15, spaceAfter=4, alignment=TA_JUSTIFY)
BULL = sty("BL",  fontName="Helvetica",      fontSize=10, textColor=VS_MID,
            leading=14, leftIndent=12, spaceAfter=2)
S_TXT= sty("ST",  fontName="Helvetica",      fontSize=10, textColor=VS_MID,   leading=14)
S_NUM= sty("SN",  fontName="Helvetica-Bold", fontSize=10, textColor=VS_SLATE, leading=14)
TH   = sty("TH",  fontName="Helvetica-Bold", fontSize=9,  textColor=WHITE,
            leading=13, alignment=TA_CENTER)
TC   = sty("TC",  fontName="Helvetica",      fontSize=9,  textColor=VS_DARK,  leading=13)
TCC  = sty("TCC", fontName="Helvetica",      fontSize=9,  textColor=VS_DARK,
            leading=13, alignment=TA_CENTER)
TOC_N= sty("TN",  fontName="Helvetica-Bold", fontSize=10, textColor=VS_SLATE, leading=14)
TOC_T= sty("TT",  fontName="Helvetica",      fontSize=10, textColor=VS_MID,   leading=14)
TOC_P= sty("TP",  fontName="Helvetica",      fontSize=10, textColor=VS_LIGHT, leading=14)
CALL = sty("CO",  fontName="Helvetica",      fontSize=9.5,textColor=VS_DARK,
            leading=14, leftIndent=8, rightIndent=8)
FOOT = sty("FT",  fontName="Helvetica",      fontSize=8,  textColor=VS_LIGHT,
            leading=11, alignment=TA_CENTER)
CTR  = sty("CT",  fontName="Helvetica",      fontSize=11, textColor=VS_MID,
            leading=17, alignment=TA_CENTER, spaceAfter=6)
CTR_B= sty("CB",  fontName="Helvetica-Bold", fontSize=15, textColor=VS_DARK,
            leading=22, alignment=TA_CENTER, spaceAfter=8)
BADGE_S = sty("BS", fontName="Helvetica-Bold", fontSize=8, textColor=WHITE,
               leading=11, alignment=TA_CENTER)

# ── Helpers ────────────────────────────────────────────────────────────────────
def HR(color=VS_BORDER, thickness=0.6):
    return HRFlowable(width="100%", thickness=thickness, color=color,
                      spaceAfter=6, spaceBefore=2)

def gap(n=6):
    return Spacer(1, n)

def bullet(text):
    return Paragraph(f"<bullet>\u2022</bullet>  {text}", BULL)

def callout(text, bg=VS_CREAM, accent=VS_SLATE):
    t = Table([[Paragraph(text, CALL)]], colWidths=[CW - 0.1])
    t.setStyle(TableStyle([
        ("BACKGROUND",    (0,0),(-1,-1), bg),
        ("LINEBEFORE",    (0,0),(0,-1),  3, accent),
        ("TOPPADDING",    (0,0),(-1,-1), 8),
        ("BOTTOMPADDING", (0,0),(-1,-1), 8),
        ("LEFTPADDING",   (0,0),(-1,-1), 12),
        ("RIGHTPADDING",  (0,0),(-1,-1), 8),
    ]))
    return t

def dtable(rows, headers, col_widths=None):
    if col_widths is None:
        col_widths = [CW / len(headers)] * len(headers)
    data = [[Paragraph(h, TH) for h in headers]] + \
           [[Paragraph(str(c), TC if i == 0 else TCC)
             for i, c in enumerate(r)] for r in rows]
    t = Table(data, colWidths=col_widths)
    t.setStyle(TableStyle([
        ("BACKGROUND",     (0,0),(-1,0),   VS_SLATE_DARK),
        ("ROWBACKGROUNDS", (0,1),(-1,-1),  [WHITE, VS_SLATE_LIGHT]),
        ("GRID",           (0,0),(-1,-1),  0.4, VS_BORDER),
        ("TOPPADDING",     (0,0),(-1,-1),  5),
        ("BOTTOMPADDING",  (0,0),(-1,-1),  5),
        ("LEFTPADDING",    (0,0),(-1,-1),  7),
        ("RIGHTPADDING",   (0,0),(-1,-1),  7),
        ("VALIGN",         (0,0),(-1,-1),  "MIDDLE"),
    ]))
    return t

def steps(items):
    """Return list of flowables for numbered steps."""
    out = []
    for num, txt in items:
        row = Table(
            [[Paragraph(num, S_NUM), Paragraph(txt, S_TXT)]],
            colWidths=[7*mm, CW - 7*mm],
            rowHeights=None,
        )
        row.setStyle(TableStyle([
            ("VALIGN",        (0,0),(-1,-1), "TOP"),
            ("TOPPADDING",    (0,0),(-1,-1), 2),
            ("BOTTOMPADDING", (0,0),(-1,-1), 2),
            ("LEFTPADDING",   (0,0),(-1,-1), 0),
            ("RIGHTPADDING",  (0,0),(-1,-1), 0),
        ]))
        out.append(row)
    return out

def badge(text, color):
    t = Table([[Paragraph(text, BADGE_S)]], colWidths=[20*mm], rowHeights=[5.5*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND",    (0,0),(-1,-1), color),
        ("TOPPADDING",    (0,0),(-1,-1), 2),
        ("BOTTOMPADDING", (0,0),(-1,-1), 2),
        ("LEFTPADDING",   (0,0),(-1,-1), 4),
        ("RIGHTPADDING",  (0,0),(-1,-1), 4),
    ]))
    return t

# ── Page drawing callbacks ─────────────────────────────────────────────────────
HEADER_H = 12 * mm
FOOTER_H = 14 * mm

def on_cover(canvas, doc):
    canvas.saveState()

    # Background — left dark panel
    canvas.setFillColor(VS_DARK)
    canvas.rect(0, 0, W * 0.58, H, fill=1, stroke=0)

    # Background — right slightly lighter panel
    canvas.setFillColor(colors.HexColor("#222222"))
    canvas.rect(W * 0.58, 0, W * 0.42, H, fill=1, stroke=0)

    # Accent vertical stripe
    canvas.setFillColor(VS_SLATE)
    canvas.rect(W * 0.58, 0, 3, H, fill=1, stroke=0)

    # Faint large isotipo watermark (right panel, lower half)
    if os.path.exists(ICON_SLATE):
        canvas.drawImage(ICON_SLATE,
                         W * 0.60, H * 0.05,
                         width=200, height=200,
                         mask='auto',
                         preserveAspectRatio=True)

    # Main logo (left panel, vertically centred-ish)
    if os.path.exists(LOGO_SLATE):
        canvas.drawImage(LOGO_SLATE,
                         MARGIN, H * 0.38,
                         width=160, height=80,
                         mask='auto',
                         preserveAspectRatio=True)

    # "Staff User Guide" label
    canvas.setFillColor(VS_SLATE)
    canvas.setFont("Helvetica", 8.5)
    canvas.drawString(MARGIN, H * 0.38 - 14, "STAFF USER GUIDE")

    # Tagline
    canvas.setFillColor(colors.HexColor("#8A9BAE"))
    canvas.setFont("Helvetica", 10)
    canvas.drawString(MARGIN, H * 0.30,
                      "Manage memberships, classes,")
    canvas.drawString(MARGIN, H * 0.30 - 15,
                      "consultations & studio rentals.")

    # Version / date
    canvas.setFillColor(colors.HexColor("#506070"))
    canvas.setFont("Helvetica", 8)
    canvas.drawString(MARGIN, H * 0.06, "v1.0  —  March 2026")

    # Bottom bar
    canvas.setFillColor(colors.HexColor("#111111"))
    canvas.rect(0, 0, W, 20, fill=1, stroke=0)

    canvas.restoreState()


def on_page(canvas, doc):
    canvas.saveState()

    # ── Header ──────────────────────────────────────────────────────────────
    canvas.setFillColor(VS_DARK)
    canvas.rect(0, H - HEADER_H, W, HEADER_H, fill=1, stroke=0)

    if os.path.exists(ICON_SLATE):
        icon_size = 6 * mm
        canvas.drawImage(ICON_SLATE,
                         MARGIN,
                         H - HEADER_H + (HEADER_H - icon_size) / 2,
                         width=icon_size, height=icon_size,
                         mask='auto',
                         preserveAspectRatio=True)

    canvas.setFillColor(VS_LIGHT)
    canvas.setFont("Helvetica", 7)
    canvas.drawString(MARGIN + 8*mm,
                      H - HEADER_H + HEADER_H / 2 - 3.5,
                      "VOLUME STUDIO  —  STAFF USER GUIDE")

    # ── Footer ──────────────────────────────────────────────────────────────
    canvas.setStrokeColor(VS_BORDER)
    canvas.setLineWidth(0.5)
    canvas.line(MARGIN, FOOTER_H - 2, W - MARGIN, FOOTER_H - 2)
    canvas.setFillColor(VS_LIGHT)
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(MARGIN, FOOTER_H - 10, "volumestudio.mx")
    canvas.drawRightString(W - MARGIN, FOOTER_H - 10, f"Page {doc.page}")

    canvas.restoreState()


# ── Document setup ─────────────────────────────────────────────────────────────
def build():
    output = "volume_studio_user_guide.pdf"

    cover_frame = Frame(0, 0, W, H,
                        leftPadding=0, rightPadding=0,
                        topPadding=0, bottomPadding=0,
                        showBoundary=0)

    content_frame = Frame(
        MARGIN,
        FOOTER_H + 2,
        CW,
        H - HEADER_H - FOOTER_H - 4,
        showBoundary=0,
    )

    doc = BaseDocTemplate(
        output,
        pagesize=A4,
        pageTemplates=[
            PageTemplate(id="Cover",   frames=[cover_frame],   onPage=on_cover),
            PageTemplate(id="Content", frames=[content_frame], onPage=on_page),
        ],
        title="Volume Studio – Staff User Guide",
        author="Volume Studio",
    )

    story = []

    # ── Cover (full-page canvas; just a tall spacer to fill the frame) ────────
    story.append(Spacer(1, H))
    story.append(NextPageTemplate("Content"))
    story.append(PageBreak())

    # ════════════════════════════════════════════════════════════════════
    # TABLE OF CONTENTS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("Contents", H1))
    story.append(HR())

    toc_items = [
        ("1.", "Getting Around",             "3"),
        ("2.", "Members",                    "3"),
        ("3.", "Subscription Plans",         "4"),
        ("4.", "Subscriptions",              "5"),
        ("5.", "Recording Payments",         "6"),
        ("6.", "Class Sessions & Bookings",  "7"),
        ("7.", "Consultations",              "8"),
        ("8.", "Space Rentals",              "9"),
        ("9.", "Quick Sale",                 "9"),
        ("10.","Finance & Accounting",       "10"),
    ]
    toc_data = [
        [Paragraph(n, TOC_N), Paragraph(t, TOC_T), Paragraph(p, TOC_P)]
        for n, t, p in toc_items
    ]
    toc = Table(toc_data, colWidths=[10*mm, CW - 26*mm, 16*mm])
    toc.setStyle(TableStyle([
        ("VALIGN",        (0,0),(-1,-1), "MIDDLE"),
        ("TOPPADDING",    (0,0),(-1,-1), 5),
        ("BOTTOMPADDING", (0,0),(-1,-1), 5),
        ("LINEBELOW",     (0,0),(-1,-2), 0.4, VS_BORDER),
    ]))
    story.append(toc)
    story.append(PageBreak())

    # ════════════════════════════════════════════════════════════════════
    # 1. GETTING AROUND
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("1. Getting Around", H1))
    story.append(HR())
    story.append(Paragraph(
        "After logging in you'll land on the <b>Volume Studio Dashboard</b>. "
        "The left sidebar is split into two groups:", BODY))
    story.append(gap(4))

    nav = Table(
        [[Paragraph("Main Menu", sty("x1", fontName="Helvetica-Bold", fontSize=10,
                                      textColor=VS_SLATE, leading=14)),
          Paragraph("Dashboard · Class Sessions · Class Calendar · "
                    "Subscriptions · Quick Sale", BODY)],
         [Paragraph("Studio & Spaces", sty("x2", fontName="Helvetica-Bold", fontSize=10,
                                            textColor=VS_SLATE, leading=14)),
          Paragraph("Members · Instructors · Consultations · "
                    "Subscription Plans · Spaces · Rentals", BODY)]],
        colWidths=[44*mm, CW - 44*mm])
    nav.setStyle(TableStyle([
        ("BACKGROUND",    (0,0),(0,-1),  VS_SLATE_LIGHT),
        ("GRID",          (0,0),(-1,-1), 0.4, VS_BORDER),
        ("VALIGN",        (0,0),(-1,-1), "TOP"),
        ("TOPPADDING",    (0,0),(-1,-1), 7),
        ("BOTTOMPADDING", (0,0),(-1,-1), 7),
        ("LEFTPADDING",   (0,0),(-1,-1), 8),
    ]))
    story.append(nav)
    story.append(gap(6))
    story.append(callout(
        "<b>Tip:</b> The Dashboard shows active subscriptions, memberships "
        "expiring within 30 days, and this week's class sessions — a great "
        "first stop every morning."))

    # ════════════════════════════════════════════════════════════════════
    # 2. MEMBERS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("2. Members", H1))
    story.append(HR())
    story.append(Paragraph(
        "Members are the people who train at the studio. You can look them up, "
        "create new profiles, and see all of their activity from one place.", BODY))

    story.append(Paragraph("Creating a new member", H2))
    for row in steps([
        ("1.", "Go to <b>Studio &amp; Spaces → Members</b> and click <b>New Member</b>."),
        ("2.", "Enter their <b>name</b> and <b>phone number</b> (required). "
               "Email and notes are optional."),
        ("3.", "Click <b>Save</b>. The member profile opens immediately."),
    ]):
        story.append(row)

    story.append(Paragraph("Finding a member", H2))
    story.append(bullet("Use the search bar at the top of the Members list."))
    story.append(bullet("Members are sorted alphabetically."))
    story.append(bullet("The member profile links to all their subscriptions, "
                        "bookings, consultations, and rentals."))

    story.append(Paragraph("Deleting a member", H2))
    story.append(callout(
        "<b>Note:</b> Deleting a member is a <i>soft delete</i> — the record is "
        "hidden but never permanently removed. All history is preserved. "
        "Their active subscriptions, bookings, and rentals are also hidden at the same time.",
        bg=colors.HexColor("#FFF7ED"), accent=colors.HexColor("#C2824A")))

    # ════════════════════════════════════════════════════════════════════
    # 3. SUBSCRIPTION PLANS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("3. Subscription Plans", H1))
    story.append(HR())
    story.append(Paragraph(
        "Plans are the templates you sell. Create a plan once, then sell it "
        "to multiple members as individual subscriptions.", BODY))

    story.append(Paragraph("Plan types", H2))
    story.append(dtable(
        [
            ["Membership", "Ongoing access (e.g. monthly unlimited)",  "Optional",  "Months"],
            ["Package",    "Fixed class bundle (e.g. 8 classes)",       "Required",  "Months / Days"],
            ["Promo",      "Limited-time promotional offer",            "Optional",  "Date or Duration"],
            ["Extra",      "One-off add-on (merch, drop-in)",           "Usually 1", "None"],
        ],
        ["Type", "Use case", "Class limit", "Duration"],
        col_widths=[28*mm, 70*mm, 28*mm, 38*mm]))

    story.append(Paragraph("Creating a plan", H2))
    for row in steps([
        ("1.", "Go to <b>Studio &amp; Spaces → Subscription Plans → New Plan</b>."),
        ("2.", "Choose a <b>Plan type</b>. The form adapts to show relevant fields only."),
        ("3.", "Set the <b>price</b>. IVA (16%) is calculated automatically at checkout."),
        ("4.", "For Packages and Memberships set an optional <b>class limit</b>."),
        ("5.", "For Promos choose <b>Expiry date</b> or <b>Duration</b> using the toggle."),
        ("6.", "Extras have no duration — leave that field blank."),
        ("7.", "Click <b>Save Plan</b>."),
    ]):
        story.append(row)

    story.append(gap(4))
    story.append(callout(
        "<b>Tip:</b> Use the filter tabs on the Plans list "
        "(Memberships / Packages / Promos / Extras) to quickly find what you need."))

    # ════════════════════════════════════════════════════════════════════
    # 4. SUBSCRIPTIONS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("4. Subscriptions", H1))
    story.append(HR())
    story.append(Paragraph(
        "A subscription is a plan sold to a specific member. It tracks start/end "
        "dates, classes used, payments received, and revenue recognised.", BODY))

    story.append(Paragraph("Creating a subscription", H2))
    for row in steps([
        ("1.", "Go to <b>Subscriptions → New Subscription</b>."),
        ("2.", "Search for an existing member or switch to <b>New Member</b> mode "
               "to create one on the spot."),
        ("3.", "Select the <b>Plan</b>."),
        ("4.", "Set the <b>start date</b>. For fixed-duration plans the end date is "
               "calculated automatically — or override it manually."),
        ("5.", "Add an optional <b>discount</b> (flat amount, pre-IVA)."),
        ("6.", "Click <b>Create Subscription</b>."),
    ]):
        story.append(row)

    story.append(Paragraph("Subscription statuses", H2))
    story.append(dtable(
        [
            ["Active",    "Running — member can attend classes"],
            ["Paused",    "Temporarily on hold"],
            ["Expired",   "Past the end date (set automatically)"],
            ["Completed", "All classes used (set automatically when limit reached)"],
            ["Cancelled", "Manually cancelled"],
        ],
        ["Status", "Meaning"],
        col_widths=[30*mm, CW - 30*mm]))

    story.append(Paragraph("Payment status badge", H2))
    story.append(Paragraph(
        "The Subscriptions list shows a colour-coded badge on every row:", BODY))
    story.append(gap(4))
    badge_rows = [
        [badge("Paid",    GREEN),
         Paragraph("Member has paid the full amount (price + IVA − discount).", BODY)],
        [badge("Partial", AMBER),
         Paragraph("Some payment received but a balance is still outstanding.", BODY)],
        [badge("Unpaid",  RED_C),
         Paragraph("No payment recorded yet.", BODY)],
    ]
    bt = Table(badge_rows, colWidths=[26*mm, CW - 26*mm])
    bt.setStyle(TableStyle([
        ("VALIGN",        (0,0),(-1,-1), "MIDDLE"),
        ("TOPPADDING",    (0,0),(-1,-1), 5),
        ("BOTTOMPADDING", (0,0),(-1,-1), 5),
        ("LINEBELOW",     (0,0),(-1,-2), 0.4, VS_BORDER),
    ]))
    story.append(bt)

    story.append(Paragraph("Reactivating a subscription", H2))
    story.append(bullet("A <b>Paused</b> subscription can be reactivated immediately."))
    story.append(bullet("An <b>Expired</b> or <b>Completed</b> subscription can be "
                        "reactivated with a new end date."))
    story.append(bullet("Use the <b>Actions</b> dropdown on the subscription detail page."))

    story.append(PageBreak())

    # ════════════════════════════════════════════════════════════════════
    # 5. RECORDING PAYMENTS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("5. Recording Payments", H1))
    story.append(HR())
    story.append(Paragraph(
        "Payments are recorded from the subscription, consultation, or rental "
        "detail page. Every payment creates a double-entry journal entry "
        "automatically — no manual bookkeeping required.", BODY))

    story.append(Paragraph("How to record a subscription payment", H2))
    for row in steps([
        ("1.", "Open the subscription and click <b>Record Payment</b>."),
        ("2.", "Enter the <b>amount received</b>."),
        ("3.", "Choose <b>Paid To</b> — where the money went:"),
    ]):
        story.append(row)

    story.append(gap(2))
    story.append(dtable(
        [
            ["Cash",          "Physical cash in the register",             "1000"],
            ["Bank Transfer", "Wire / deposit to the studio bank account", "1010"],
            ["Card Terminal", "Card reader / POS terminal",                "1020"],
        ],
        ["Method", "When to use", "GL account"],
        col_widths=[36*mm, 100*mm, 28*mm]))
    story.append(gap(6))

    for row in steps([
        ("4.", "Set the <b>payment date</b>."),
        ("5.", "Click <b>Save Payment</b>."),
    ]):
        story.append(row)

    story.append(gap(6))
    story.append(callout(
        "<b>Revenue recognition:</b> When a payment is recorded, the money first "
        "goes into <i>Deferred Revenue</i> (a liability). Revenue is recognised "
        "over time for Memberships and Promos, per class attended for Packages, "
        "and immediately on redemption for Extras."))

    # ════════════════════════════════════════════════════════════════════
    # 6. CLASS SESSIONS & BOOKINGS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("6. Class Sessions &amp; Bookings", H1))
    story.append(HR())
    story.append(Paragraph(
        "Class sessions are scheduled classes that members book into. "
        "Bookings are linked to subscriptions so attendance is tracked automatically.", BODY))

    story.append(Paragraph("Creating a class session", H2))
    for row in steps([
        ("1.", "Go to <b>Class Sessions → New Session</b>."),
        ("2.", "Choose the <b>Instructor</b>, session name, date/time, and duration."),
        ("3.", "Set an optional <b>capacity</b> cap."),
        ("4.", "Click <b>Save</b>. The session appears on the Class Calendar."),
    ]):
        story.append(row)

    story.append(Paragraph("Adding a booking", H2))
    for row in steps([
        ("1.", "Open a session and click <b>Add Booking</b>."),
        ("2.", "Search for the member. The system auto-assigns their "
               "soonest-expiring active subscription."),
        ("3.", "Click <b>Book</b>."),
    ]):
        story.append(row)

    story.append(Paragraph("Checking in members", H2))
    story.append(bullet("On the session page, click <b>Check In</b> next to a booking."))
    story.append(bullet("This increments the member's <i>classes used</i> counter."))
    story.append(bullet(
        "For <b>Package</b> plans a portion of deferred revenue is recognised at each check-in."))
    story.append(bullet(
        "If the class limit is reached the subscription moves to <b>Completed</b> automatically."))
    story.append(bullet("Mark absentees as <b>No Show</b> to reverse the counter if needed."))

    # ════════════════════════════════════════════════════════════════════
    # 7. CONSULTATIONS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("7. Consultations", H1))
    story.append(HR())
    story.append(Paragraph(
        "Consultations are one-on-one sessions (e.g. nutrition, diet advice) "
        "charged as a flat fee.", BODY))

    for row in steps([
        ("1.", "Go to <b>Studio &amp; Spaces → Consultations → New Consultation</b>."),
        ("2.", "Select the <b>Member</b> and <b>Instructor</b>."),
        ("3.", "Set the <b>date/time</b> and <b>duration</b>."),
        ("4.", "Enter the <b>amount</b>."),
        ("5.", "Click <b>Save</b>."),
        ("6.", "Open the consultation and click <b>Record Payment</b> when payment is received. "
               "Revenue is recognised immediately."),
    ]):
        story.append(row)

    story.append(Paragraph("Statuses", H2))
    story.append(dtable(
        [
            ["Scheduled", "Upcoming"],
            ["Completed", "Session took place"],
            ["No Show",   "Member did not attend"],
            ["Cancelled", "Cancelled before taking place"],
        ],
        ["Status", "Meaning"],
        col_widths=[30*mm, CW - 30*mm]))

    # ════════════════════════════════════════════════════════════════════
    # 8. SPACE RENTALS
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("8. Space Rentals", H1))
    story.append(HR())
    story.append(Paragraph(
        "Studio rooms can be rented out by the hour. Set up each room once "
        "under Spaces, then create Rentals against it.", BODY))

    story.append(Paragraph("Setting up a space", H2))
    for row in steps([
        ("1.", "Go to <b>Studio &amp; Spaces → Spaces → New Space</b>."),
        ("2.", "Enter the name (e.g. \"Sala Principal\"), optional description, "
               "capacity, and <b>hourly rate</b>."),
        ("3.", "Click <b>Save</b>."),
    ]):
        story.append(row)

    story.append(Paragraph("Creating a rental", H2))
    for row in steps([
        ("1.", "Go to <b>Studio &amp; Spaces → Rentals → New Rental</b>."),
        ("2.", "Select the <b>Space</b>."),
        ("3.", "Enter the renter's <b>name, phone, and email</b>."),
        ("4.", "Set <b>start and end date/time</b>."),
        ("5.", "Enter the agreed <b>amount</b>. IVA is calculated automatically."),
        ("6.", "Click <b>Save</b> and record payment when received."),
    ]):
        story.append(row)

    # ════════════════════════════════════════════════════════════════════
    # 9. QUICK SALE
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("9. Quick Sale", H1))
    story.append(HR())
    story.append(Paragraph(
        "<b>Quick Sale</b> is the fastest way to sell a one-off item — "
        "merchandise, a drop-in class, a single session — without going "
        "through the full subscription flow.", BODY))

    for row in steps([
        ("1.", "Click <b>Quick Sale</b> in the main menu."),
        ("2.", "Search for the member or type a new name."),
        ("3.", "Choose the <b>Extra</b> plan to sell (e.g. \"Drop-in\", \"Protein Bar\")."),
        ("4.", "Add an optional discount."),
        ("5.", "Click <b>Create</b> — you land directly on the payment page."),
        ("6.", "Record the payment and select <b>Paid To</b> (Cash / Bank / Card)."),
    ]):
        story.append(row)

    story.append(gap(4))
    story.append(callout(
        "<b>Tip:</b> Quick Sale only shows <i>Extra</i> type plans. "
        "Make sure your one-off products are created as Extra plans under "
        "Subscription Plans first."))

    story.append(PageBreak())

    # ════════════════════════════════════════════════════════════════════
    # 10. FINANCE & ACCOUNTING
    # ════════════════════════════════════════════════════════════════════
    story.append(Paragraph("10. Finance &amp; Accounting", H1))
    story.append(HR())
    story.append(Paragraph(
        "Volume Studio uses double-entry bookkeeping. Every payment, recognition "
        "event, and refund creates journal entries automatically — you never "
        "need to enter them manually.", BODY))

    story.append(Paragraph("Chart of accounts", H2))
    story.append(dtable(
        [
            ["1000", "Cash",                 "Physical register / cash drawer"],
            ["1010", "Bank Transfer",        "Studio bank account"],
            ["1020", "Card Terminal",        "POS terminal receipts"],
            ["2100", "IVA Payable",          "16% VAT collected, owed to SAT"],
            ["2200", "Deferred Revenue",     "Prepaid subscriptions not yet earned"],
            ["4000", "Subscription Revenue", "Earned subscription income"],
            ["4020", "Consultation Revenue", "Consultation income"],
            ["4030", "Rental Revenue",       "Space rental income"],
        ],
        ["Code", "Account", "Description"],
        col_widths=[18*mm, 50*mm, CW - 68*mm]))

    story.append(Paragraph("Revenue recognition schedule", H2))
    story.append(dtable(
        [
            ["Membership / Promo", "Monthly",       "1/N of deferred revenue per month"],
            ["Package",            "Per check-in",  "Deferred balance ÷ remaining classes"],
            ["Extra",              "On redemption", "All deferred revenue at once"],
            ["Consultation",       "On payment",    "Immediate — no deferral"],
            ["Space Rental",       "On payment",    "Immediate — no deferral"],
        ],
        ["Type", "Trigger", "How much"],
        col_widths=[42*mm, 38*mm, CW - 80*mm]))

    story.append(gap(8))
    story.append(callout(
        "<b>Important:</b> Cash collected today appears as <i>Deferred Revenue</i> "
        "(a liability on the balance sheet) until the service is delivered. "
        "The P&amp;L shows revenue as it is <i>earned</i>, not when cash is received. "
        "Use the <b>Transactions</b> section in the sidebar to view the full journal."))

    # ── Back page ──────────────────────────────────────────────────────────────
    story.append(PageBreak())
    story.append(Spacer(1, 40*mm))

    if os.path.exists(ICON_SLATE):
        ico_tbl = Table(
            [[__import__('reportlab.platypus', fromlist=['Image']).Image(
                ICON_SLATE, width=28*mm, height=28*mm)]],
            colWidths=[CW])
        ico_tbl.setStyle(TableStyle([("ALIGN", (0,0),(-1,-1), "CENTER")]))
        story.append(ico_tbl)

    story.append(gap(10))
    story.append(Paragraph("Need help?", CTR_B))
    story.append(Paragraph(
        "If you run into something unexpected, reach out to your admin.<br/>"
        "All deletions are soft — nothing is ever permanently lost.",
        CTR))
    story.append(Spacer(1, 12*mm))
    story.append(HR(color=VS_SLATE))
    story.append(gap(4))
    story.append(Paragraph("Volume Studio  •  Staff User Guide  •  v1.0  •  March 2026", FOOT))

    doc.build(story)
    print(f"Written → {output}")


if __name__ == "__main__":
    build()
