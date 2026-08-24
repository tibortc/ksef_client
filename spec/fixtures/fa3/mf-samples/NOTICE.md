# FA(3) sample invoices — Ministerstwo Finansów

The twenty-six XML files beside this notice are the Ministry of Finance's own worked examples of
the FA(3) logical structure. They are redistributed here, unmodified apart from their filenames,
as test fixtures. **They are not packaged in the gem** — `ksef_client.gemspec` ships `lib/**` and
`docs/*.md` only.

## Source

| | |
|---|---|
| Package | *Przykładowe pliki dla struktury logicznej e-Faktury FA(3)* |
| URL | https://ksef.podatki.gov.pl/media/e5cia0ey/przykladowe-pliki-dla-struktury-logicznej-e-faktury-fa-3.zip |
| Retrieved | 2026-08-24 |
| Archive SHA-256 | `41ebd3c57144951c65d68a36fbe433285b5791a86a8bd46cb059503e3f8b1e10` |
| Archive size | 200 512 bytes |
| Publisher | Ministerstwo Finansów, via `ksef.podatki.gov.pl` |

Linked from https://ksef.podatki.gov.pl/pliki-do-pobrania-ksef-20/. The archive also contains
*Opisy przykładów dla struktury logicznej FA(3)* (a five-page descriptions PDF), which is **not**
redistributed here — it is referenced by checksum in `docs/REFERENCE.md` §1.5 instead.

## Attribution and terms

`podatki.gov.pl` carries this statement site-wide:

> Korzystanie z treści opublikowanych w serwisie podatki.gov.pl, niezależnie od celu i sposobu
> korzystania, nie wymaga zgody Ministerstwa Finansów. Treści znaczone w serwisie jako treści
> będące przedmiotem praw autorskich, o ile nie jest to stwierdzone inaczej, są udostępniane na
> licencji Creative Commons Uznanie Autorstwa 3.0 Polska.

> *Using content published on the podatki.gov.pl service, regardless of the purpose and manner of
> use, does not require the consent of the Ministry of Finance. Content marked on the service as
> being subject to copyright is, unless stated otherwise, made available under the Creative
> Commons Attribution 3.0 Poland licence.*

This attribution is provided on that basis. **One caveat is recorded honestly:** the files are
hosted on `ksef.podatki.gov.pl`, a subdomain that carries no licence statement of its own, and the
files themselves bear no internal notice. Whether the `podatki.gov.pl` statement reaches its
subdomain is an interpretive question nobody has answered in writing; the redistribution decision
was taken by the project's maintainer on 2026-08-24 (DESIGN.md §12), and `docs/REFERENCE.md` §1.5
records the reasoning. Note that the MIT grant covering this gem's other Ministry artifacts does
**not** apply here — that licence arrives via the `CIRFMF` GitHub repositories, and these files are
in none of them.

## Filenames

Renamed to ASCII, zero-padded so they sort. Upstream names carry Polish diacritics and an
inconsistent `FA_3_`/`Fa_3_` prefix, which travel badly across case-insensitive filesystems and
Windows checkouts. The **bytes are unmodified**, and it is the bytes that `docs/artifacts.sha256`
pins.

| Here | Upstream |
|---|---|
| `przyklad-01.xml` … `przyklad-13.xml` | `FA_3_Przykład_1.xml` … `FA_3_Przykład_13.xml` |
| `przyklad-14.xml`, `przyklad-17.xml` … `przyklad-20.xml` | `Fa_3_Przykład_14.xml`, `Fa_3_Przykład_17.xml` … `Fa_3_Przykład_20.xml` |
| `przyklad-15.xml`, `przyklad-16.xml`, `przyklad-21.xml` … `przyklad-26.xml` | `FA_3_Przykład_15.xml`, `FA_3_Przykład_16.xml`, `FA_3_Przykład_21.xml` … `FA_3_Przykład_26.xml` |

## What is in them

All twenty-six validate against the pinned FA(3) XSD with zero errors (measured 2026-08-24). They
are the **only** corpus of non-`VAT` invoice types in existence — no `CIRFMF` repository contains
one, across every branch and the whole history of all six.

| `RodzajFaktury` | Count | Examples |
|---|---|---|
| `VAT` | 12 | 01 04 08 09 19 20 21 22 23 24 25 26 |
| `KOR` | 5 | 02 03 05 06 07 |
| `KOR_ZAL` | 3 | 11 12 13 |
| `ROZ` | 2 | 14 17 |
| `UPR` | 2 | 15 16 |
| `KOR_ROZ` | 1 | 18 |
| `ZAL` | 1 | 10 |
