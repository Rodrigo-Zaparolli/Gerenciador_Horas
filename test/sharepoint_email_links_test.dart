import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gerenciador_horas/features/project_emails/email_document.dart';
import 'package:gerenciador_horas/features/project_emails/sharepoint_email_links.dart';

void main() {
  const url =
      'https://cyncly.sharepoint.com/:f:/s/Client/opaque-token?e=example';
  const title = 'Enterprise Produção Completa - BR Cantanhede Moveis';
  test('materials link displays customer name while preserving original URL', () {
    const body = 'Caminho dos Materiais da Implantação → $url';
    final labels = emailClientLinkLabels(body, {url: title},
        clientName: 'BR Cantanhede Moveis');
    final html = emailBodyHtml(body, linkLabels: labels);
    expect(html, contains('href="$url"'));
    expect(html, contains('BR Cantanhede Moveis</a>'));
    expect(html, isNot(contains('>$title</a>')));
    expect(emailLinkDisplayText(body, labels), contains('📁 BR Cantanhede Moveis'));
  });
  test('resolved name labels the original exact link and escapes HTML', () {
    final html = emailBodyHtml('Materiais: $url',
        linkLabels: {url: '$title <teste> & dados'});
    expect(html, contains('href="$url"'));
    expect(html, contains('📁 $title &lt;teste&gt; &amp; dados</a>'));
    expect(emailBodyHtml('$url-other', linkLabels: {url: title}),
        isNot(contains(title)));
    expect(emailLinkDisplayText('$url\n$url-other', {url: title}),
        '📁 $title\n$url-other');
  });
  test('only exact HTTPS SharePoint addresses may be resolved', () {
    expect(sharePointLinksInBody('$url\n$url\nhttps://example.com/x'), [url]);
    for (final invalid in [
      'http://cyncly.sharepoint.com/a',
      'https://cyncly.sharepoint.com.evil.test/a',
      'https://user:pass@cyncly.sharepoint.com/a',
      'https://cyncly.sharepoint.com:123/a'
    ]) {
      expect(isSharePointFolderLink(invalid), false);
    }
    expect(
        validSharePointNames({
          url: title,
          'https://evil.test': title,
          '$url/a': '',
          '$url/b': 42
        }),
        {url: title});
  });
  test('generated MIME contains a clickable title with unchanged destination',
      () {
    final contact = EmailContact(name: 'Cliente', email: 'cliente@example.com')
      ..destination = 'Para';
    final draft = utf8.decode(buildEmailDraft(
        subject: 'Projeto',
        body: 'Materiais: $url',
        contacts: [contact],
        linkLabels: {url: title}));
    final htmlEncoded = RegExp(
            r'Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n([A-Za-z0-9+/=\r\n]+)')
        .firstMatch(draft)![1]!
        .replaceAll(RegExp(r'\s'), '');
    final html = utf8.decode(base64Decode(htmlEncoded));
    expect(html, contains('href="$url">📁 $title</a>'));
  });
}
