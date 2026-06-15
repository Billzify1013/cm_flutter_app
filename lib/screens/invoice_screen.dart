import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/error_util.dart';
import '../config/app_config.dart';

class InvoiceScreen extends StatefulWidget {
  final String bookingId, guestName;
  const InvoiceScreen({super.key, required this.bookingId, required this.guestName});
  @override State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = await ApiService.instance.getUserId();
      final res = await ApiService.instance.postData(
        AppConfig.invoiceUnified,
        {'user_id': uid, 'booking_id': widget.bookingId},
      );
      if (!mounted) return;
      setState(() { _data = Map<String, dynamic>.from(res.data); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  bool get _isInvoice => _data?['invoice_created'] == true;
  bool get _gst       => _data?['gststatus'] == true;
  double _n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0.0;
  String _f(dynamic v, {int d = 2}) => _n(v).toStringAsFixed(d);
  String _rs(dynamic v, {int d = 2}) => 'Rs. ${_f(v, d: d)}';

  Future<Uint8List> _buildPdf() async {
    if (_data == null) return Uint8List(0);

    final h     = (_data!['hotel']   as Map? ?? {}).map((k,v) => MapEntry(k.toString(), v));
    final b     = (_data!['booking'] as Map? ?? {}).map((k,v) => MapEntry(k.toString(), v));
    final inv   = (_data!['invoice'] as Map?)?.map((k,v) => MapEntry(k.toString(), v));
    final rooms = (_data!['rooms']     as List?) ?? [];
    final pos   = (_data!['pos_items'] as List?) ?? [];
    final pays  = (_data!['payments']  as List?) ?? [];
    final slabs = (_data!['tax_slabs'] as List?) ?? [];
    final gd    = (_data!['guest_gst'] as Map?)?.map((k,v) => MapEntry(k.toString(), v));
    final terms = (_data!['hotel'] as Map?)?['terms'] as List? ?? [];

    final grand  = _n(b['amount_after_tax']);
    final base   = _n(b['amount_before_tax']);
    final taxAmt = _n(b['tax']);
    final adv    = _n(b['advance_amount']);
    final rem    = _n(b['remaining_amount']);
    final isPaid = rem <= 0;
    final isPartial = adv > 0 && !isPaid;

    final fontR = await PdfGoogleFonts.nunitoRegular();
    final fontB = await PdfGoogleFonts.nunitoBold();

    pw.TextStyle ts(double size, {bool isBold = false, PdfColor color = PdfColors.black}) =>
        pw.TextStyle(font: isBold ? fontB : fontR, fontSize: size, color: color);

    pw.Widget cell(String v, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
            child: pw.Text(v, style: ts(8, isBold: bold), textAlign: align));

    pw.Widget sRow(String l, String v, {bool bold = false}) =>
        pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(l, style: ts(bold ? 9 : 8, isBold: bold)),
              pw.Text(v, style: ts(bold ? 10 : 8, isBold: bold)),
            ]));

    // Logo
    pw.ImageProvider? logoImg;
    try {
      final url = h['logo_url']?.toString() ?? '';
      if (url.isNotEmpty) logoImg = await networkImage(url);
    } catch (_) {}

    final pdf = pw.Document();

    pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [

              // ── HEADER ──
              pw.Center(child: pw.Column(children: [
                if (logoImg != null)
                  pw.Container(width: 80, height: 80,
                      child: pw.Image(logoImg, fit: pw.BoxFit.contain))
                else
                  pw.Container(width: 70, height: 70,
                      decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle, color: PdfColors.grey300),
                      child: pw.Center(child: pw.Text(
                          (h['name']?.toString() ?? 'H')[0].toUpperCase(),
                          style: ts(28, isBold: true)))),
                pw.SizedBox(height: 8),
                pw.Text(h['name']?.toString() ?? '',
                    style: ts(14, isBold: true), textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 3),
                pw.Text(
                    '${h['address'] ?? ''}, ${h['zipcode'] ?? ''}, ${h['country'] ?? ''}',
                    style: ts(9, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
                pw.SizedBox(height: 2),
                pw.Text(
                    '${_gst ? 'GST Number: ${h['gstin']}  ,  ' : ''}PH: ${h['contact']}',
                    style: ts(9, isBold: true), textAlign: pw.TextAlign.center),
              ])),

              pw.SizedBox(height: 12),
              pw.Divider(thickness: 0.8, color: PdfColors.grey400),
              pw.SizedBox(height: 8),

              // ── 2-COL INFO ──
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Expanded(child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(_isInvoice ? 'Invoice' : 'Proforma Invoice', style: ts(9)),
                  if (_isInvoice && inv != null) ...[
                    pw.SizedBox(height: 3),
                    pw.Text('Invoice Number : ${inv['invoice_number']}', style: ts(9)),
                    pw.Text('Invoice Date: ${inv['invoice_date']}', style: ts(9)),
                  ],
                  pw.SizedBox(height: 3),
                  pw.Text('Check-In: ${b['checkin']}', style: ts(9)),
                  pw.Text('Check-Out: ${b['checkout']}', style: ts(9)),
                  pw.Text('Source: ${b['channel'] ?? '-'}', style: ts(9)),
                ])),
                pw.Expanded(child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Guest Name: ${b['guest_name']}', style: ts(9)),
                  pw.Text('Guest Phone: ${b['guest_phone'] ?? ''}', style: ts(9)),
                  pw.Text('Total Nights: ${b['nights']}', style: ts(9)),
                  pw.Text('Number of Guests: ${b['total_guests']}', style: ts(9)),
                  pw.Text('Number of Rooms: ${b['no_of_rooms']}', style: ts(9)),
                ])),
              ]),

              // ── BILL TO (if GST) ──
              if (gd != null && _gst) ...[
                pw.SizedBox(height: 8),
                pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Text('BILL TO', style: ts(8, isBold: true, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text(gd['company']?.toString() ?? '',
                          style: ts(10, isBold: true)),
                      pw.Text('GSTIN: ${gd['gstnumber']}', style: ts(9)),
                      if ((gd['address']?.toString() ?? '').isNotEmpty)
                        pw.Text(gd['address'].toString(), style: ts(9)),
                      if ((gd['state']?.toString() ?? '').isNotEmpty)
                        pw.Text('State: ${gd['state'].toString().split('|').last}', style: ts(9)),
                    ])),
              ],

              pw.SizedBox(height: 10),

              // ── ROOM TABLE ──
              if (rooms.isNotEmpty) ...[
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.7),
                    columnWidths: _gst
                        ? { 0: const pw.FlexColumnWidth(0.7),
                      1: const pw.FlexColumnWidth(2.2),
                      2: const pw.FlexColumnWidth(1.4),
                      3: const pw.FlexColumnWidth(0.7),
                      4: const pw.FlexColumnWidth(1.2),
                      5: const pw.FlexColumnWidth(0.7),
                      6: const pw.FlexColumnWidth(1.2),
                      7: const pw.FlexColumnWidth(1.4) }
                        : { 0: const pw.FlexColumnWidth(0.7),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(1.8),
                      3: const pw.FlexColumnWidth(1.2),
                      4: const pw.FlexColumnWidth(1.8) },
                    children: [
                      pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.white),
                          children: (_gst
                              ? ['Qty','Rooms','Price','Nights','HSN/SAC','GST','Total Tax','Total']
                              : ['Qty','Rooms','Price','Nights','Total'])
                              .map((c) => cell(c, bold: true)).toList()),
                      ...rooms.map((r) {
                        final rm = Map<String,dynamic>.from(r as Map);
                        return pw.TableRow(children: (_gst
                            ? ['${rm['count']??1}', rm['room_type']?.toString()??'-',
                          _f(rm['price'],d:2), '${rm['nights']??1}',
                          rm['hsn_code']?.toString()?? '996311',
                          '${rm['gst_pct']}%', _f(rm['tax_amount']), _f(rm['total'])]
                            : ['${rm['count']??1}', rm['room_type']?.toString()??'-',
                          _f(rm['price'],d:2), '${rm['nights']??1}', _f(rm['total'])])
                            .map((v) => cell(v)).toList());
                      }),
                    ]),
                pw.SizedBox(height: 8),
              ],

              // ── POS TABLE ──
              if (pos.isNotEmpty) ...[
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.7),
                    columnWidths: _gst
                        ? { 0: const pw.FlexColumnWidth(2.5), 1: const pw.FlexColumnWidth(0.7),
                      2: const pw.FlexColumnWidth(1.3), 3: const pw.FlexColumnWidth(0.7),
                      4: const pw.FlexColumnWidth(1.3), 5: const pw.FlexColumnWidth(1.3) }
                        : { 0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(1),
                      2: const pw.FlexColumnWidth(1.8), 3: const pw.FlexColumnWidth(1.8) },
                    children: [
                      pw.TableRow(children: (_gst
                          ? ['Item','Qty','Rate','GST%','GST Amt','Total']
                          : ['Item','Qty','Rate','Total'])
                          .map((c) => cell(c, bold: true)).toList()),
                      ...pos.map((p) {
                        final pm = Map<String,dynamic>.from(p as Map);
                        return pw.TableRow(children: (_gst
                            ? [pm['product_name']?.toString()??'-','${pm['quantity']}',
                          _f(pm['rate']),'${pm['gst_rate']}%',
                          _f(pm['gst_amount']),_f(pm['total_amount'])]
                            : [pm['product_name']?.toString()??'-','${pm['quantity']}',
                          _f(pm['rate']),_f(pm['total_amount'])])
                            .map((v) => cell(v)).toList());
                      }),
                    ]),
                pw.SizedBox(height: 8),
              ],

              // ── PAYMENTS + SUMMARY ──
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                // Payment table
                pw.Expanded(child: pays.isNotEmpty
                    ? pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.7),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1.5),
                      1: pw.FlexColumnWidth(1.5),
                      2: pw.FlexColumnWidth(1),
                    },
                    children: [
                      pw.TableRow(children: ['Date','Amount','Mode']
                          .map((c) => cell(c, bold: true)).toList()),
                      ...pays.map((p) {
                        final pm = Map<String,dynamic>.from(p as Map);
                        return pw.TableRow(children: [
                          pm['date']?.toString() ?? '',
                          _f(pm['amount']),
                          pm['mode']?.toString() ?? '',
                        ].map((v) => cell(v)).toList());
                      }),
                    ])
                    : pw.SizedBox()),
                pw.SizedBox(width: 12),

                // Summary box
                pw.Container(
                    width: 195,
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey500, width: 0.7)),
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // Payment status section
                          pw.Container(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text('Payment Status', style: ts(8)),
                                    pw.SizedBox(height: 4),
                                    pw.Align(
                                        alignment: pw.Alignment.centerLeft,
                                        child: pw.Container(
                                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: pw.BoxDecoration(
                                                color: isPaid
                                                    ? PdfColors.green100
                                                    : isPartial
                                                    ? PdfColors.orange100
                                                    : PdfColors.red50,
                                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3))),
                                            child: pw.Text(
                                                isPaid ? 'PAID' : isPartial ? 'PARTIAL' : 'DUE',
                                                style: ts(8, isBold: true,
                                                    color: isPaid
                                                        ? PdfColors.green900
                                                        : isPartial
                                                        ? PdfColors.orange900
                                                        : PdfColors.red900)))),
                                    pw.SizedBox(height: 4),
                                    pw.Text('Total Paid Amount: ${_rs(adv)}',
                                        style: ts(8, isBold: true)),
                                    if (!isPaid)
                                      pw.Text('Due Amount: ${_rs(rem)}',
                                          style: ts(8, isBold: true, color: PdfColors.red700)),
                                  ])),
                          pw.Container(height: 0.7, color: PdfColors.grey500),
                          if (_gst) ...[
                            sRow('SUBTOTAL:', _rs(base)),
                            sRow('Tax Amount:', _rs(taxAmt)),
                            pw.Container(height: 0.5, color: PdfColors.grey300),
                          ],
                          sRow('Grand Total:', _rs(grand), bold: true),
                        ])),
              ]),

              pw.SizedBox(height: 12),

              // ── TAX TABLE ──
              if (slabs.isNotEmpty && _gst) ...[
                pw.Text('Tax Descriptions', style: ts(10, isBold: true)),
                pw.SizedBox(height: 5),
                pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.7),
                    columnWidths: const {
                      0: pw.FlexColumnWidth(1.2), 1: pw.FlexColumnWidth(0.8),
                      2: pw.FlexColumnWidth(0.8), 3: pw.FlexColumnWidth(1.5),
                      4: pw.FlexColumnWidth(1.5), 5: pw.FlexColumnWidth(1.5),
                    },
                    children: [
                      pw.TableRow(children: ['Tax','CGST','SGST','CGST Amount','SGST Amount','Total Amount']
                          .map((c) => cell(c, bold: true)).toList()),
                      ...slabs.map((s) {
                        final sm = Map<String,dynamic>.from(s as Map);
                        return pw.TableRow(children: [
                          sm['name']?.toString() ?? '',
                          '${sm['cgst']} %',
                          '${sm['sgst']} %',
                          'Rs. ${_f(sm['cgst_amount'])}',
                          'Rs. ${_f(sm['sgst_amount'] ?? sm['cgst_amount'])}',
                          'Rs. ${_f(sm['total_amount'])}',
                        ].map((v) => cell(v)).toList());
                      }),
                    ]),
                pw.SizedBox(height: 12),
              ],

              // ── TERMS (sirf proforma mein) ──
              if (!_isInvoice && terms.isNotEmpty) ...[
                pw.Text('Terms & Conditions', style: ts(9, isBold: true)),
                pw.SizedBox(height: 4),
                ...terms.take(8).map((t) => pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text('• ${t.toString()}',
                        style: ts(7, color: PdfColors.grey700)))),
                pw.SizedBox(height: 10),
              ],

              pw.Spacer(),

              // ── SIGNATURES ──
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Guest Signature', style: ts(8, color: PdfColors.grey600)),
                pw.Text('Authorised Signature', style: ts(8, color: PdfColors.grey600)),
              ]),
            ])));

    return pdf.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8E8E4),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a1a),
        elevation: 0,
        title: Text(
            _loading ? 'Invoice' : (_isInvoice ? 'Tax Invoice' : 'Proforma Invoice'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white)),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? _skeleton()
          : _error != null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ]))
          : Theme(
        // Override purple color to black
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF1a1a1a),
              secondary: const Color(0xFF1a1a1a),
            ),
            iconTheme: const IconThemeData(color: Color(0xFF1a1a1a)),
            textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1a1a1a))),
          ),
        child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: PdfPreview(
            build: (_) => _buildPdf(),
            canDebug: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: true,
            allowSharing: true,
            pdfFileName: 'invoice_${widget.bookingId}.pdf',
            previewPageMargin: const EdgeInsets.all(8),
            maxPageWidth: 800,
            scrollViewDecoration: const BoxDecoration(
                color: Color(0xFFE8E8E4)),
            actionBarTheme: const PdfActionBarTheme(
              backgroundColor: Color(0xFF1a1a1a),
              iconColor: Colors.white,
              textStyle: TextStyle(color: Colors.white),
            ),
              actions: const [],
            ))),
    );
  }

  Widget _skeleton() => Shimmer.fromColors(
      baseColor: const Color(0xFFDDDDDA),
      highlightColor: const Color(0xFFF0F0EC),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(height: 120, color: Colors.white),
        const SizedBox(height: 8),
        ...List.generate(10, (_) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            height: 30, color: Colors.white)),
      ]));
}