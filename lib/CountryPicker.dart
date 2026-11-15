import 'package:flutter/material.dart';
import 'KaidoseBrand.dart';

/// One country and its international calling code.
class Country {
  final String iso; // "US"
  final String name; // "United States"
  final String dial; // "1" (no plus)

  const Country(this.iso, this.name, this.dial);

  /// The flag emoji, built from the ISO code.
  String get flag => String.fromCharCodes(
      iso.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 65));

  static final Country unitedStates = byIso('US')!;

  static Country? byIso(String? iso) {
    if (iso == null) return null;
    final key = iso.toUpperCase();
    for (final c in all) {
      if (c.iso == key) return c;
    }
    return null;
  }

  static final List<Country> all = _raw.map((line) {
    final p = line.split('|');
    return Country(p[0], p[1], p[2]);
  }).toList(growable: false);

  // ISO | name | calling code. Alphabetical by name.
  static const List<String> _raw = [
    'AF|Afghanistan|93', 'AL|Albania|355', 'DZ|Algeria|213',
    'AD|Andorra|376', 'AO|Angola|244', 'AG|Antigua and Barbuda|1',
    'AR|Argentina|54', 'AM|Armenia|374', 'AU|Australia|61',
    'AT|Austria|43', 'AZ|Azerbaijan|994', 'BS|Bahamas|1',
    'BH|Bahrain|973', 'BD|Bangladesh|880', 'BB|Barbados|1',
    'BY|Belarus|375', 'BE|Belgium|32', 'BZ|Belize|501',
    'BJ|Benin|229', 'BT|Bhutan|975', 'BO|Bolivia|591',
    'BA|Bosnia and Herzegovina|387', 'BW|Botswana|267', 'BR|Brazil|55',
    'BN|Brunei|673', 'BG|Bulgaria|359', 'BF|Burkina Faso|226',
    'BI|Burundi|257', 'KH|Cambodia|855', 'CM|Cameroon|237',
    'CA|Canada|1', 'CV|Cape Verde|238', 'CF|Central African Republic|236',
    'TD|Chad|235', 'CL|Chile|56', 'CN|China|86',
    'CO|Colombia|57', 'KM|Comoros|269', 'CG|Congo|242',
    'CD|Congo (DRC)|243', 'CR|Costa Rica|506', 'CI|Côte d\'Ivoire|225',
    'HR|Croatia|385', 'CU|Cuba|53', 'CY|Cyprus|357',
    'CZ|Czechia|420', 'DK|Denmark|45', 'DJ|Djibouti|253',
    'DM|Dominica|1', 'DO|Dominican Republic|1', 'EC|Ecuador|593',
    'EG|Egypt|20', 'SV|El Salvador|503', 'GQ|Equatorial Guinea|240',
    'ER|Eritrea|291', 'EE|Estonia|372', 'SZ|Eswatini|268',
    'ET|Ethiopia|251', 'FJ|Fiji|679', 'FI|Finland|358',
    'FR|France|33', 'GA|Gabon|241', 'GM|Gambia|220',
    'GE|Georgia|995', 'DE|Germany|49', 'GH|Ghana|233',
    'GR|Greece|30', 'GD|Grenada|1', 'GT|Guatemala|502',
    'GN|Guinea|224', 'GW|Guinea-Bissau|245', 'GY|Guyana|592',
    'HT|Haiti|509', 'HN|Honduras|504', 'HK|Hong Kong|852',
    'HU|Hungary|36', 'IS|Iceland|354', 'IN|India|91',
    'ID|Indonesia|62', 'IR|Iran|98', 'IQ|Iraq|964',
    'IE|Ireland|353', 'IL|Israel|972', 'IT|Italy|39',
    'JM|Jamaica|1', 'JP|Japan|81', 'JO|Jordan|962',
    'KZ|Kazakhstan|7', 'KE|Kenya|254', 'KI|Kiribati|686',
    'XK|Kosovo|383', 'KW|Kuwait|965', 'KG|Kyrgyzstan|996',
    'LA|Laos|856', 'LV|Latvia|371', 'LB|Lebanon|961',
    'LS|Lesotho|266', 'LR|Liberia|231', 'LY|Libya|218',
    'LI|Liechtenstein|423', 'LT|Lithuania|370', 'LU|Luxembourg|352',
    'MO|Macau|853', 'MG|Madagascar|261', 'MW|Malawi|265',
    'MY|Malaysia|60', 'MV|Maldives|960', 'ML|Mali|223',
    'MT|Malta|356', 'MH|Marshall Islands|692', 'MR|Mauritania|222',
    'MU|Mauritius|230', 'MX|Mexico|52', 'FM|Micronesia|691',
    'MD|Moldova|373', 'MC|Monaco|377', 'MN|Mongolia|976',
    'ME|Montenegro|382', 'MA|Morocco|212', 'MZ|Mozambique|258',
    'MM|Myanmar|95', 'NA|Namibia|264', 'NR|Nauru|674',
    'NP|Nepal|977', 'NL|Netherlands|31', 'NZ|New Zealand|64',
    'NI|Nicaragua|505', 'NE|Niger|227', 'NG|Nigeria|234',
    'KP|North Korea|850', 'MK|North Macedonia|389', 'NO|Norway|47',
    'OM|Oman|968', 'PK|Pakistan|92', 'PW|Palau|680',
    'PS|Palestine|970', 'PA|Panama|507', 'PG|Papua New Guinea|675',
    'PY|Paraguay|595', 'PE|Peru|51', 'PH|Philippines|63',
    'PL|Poland|48', 'PT|Portugal|351', 'PR|Puerto Rico|1',
    'QA|Qatar|974', 'RO|Romania|40', 'RU|Russia|7',
    'RW|Rwanda|250', 'KN|Saint Kitts and Nevis|1', 'LC|Saint Lucia|1',
    'VC|Saint Vincent and the Grenadines|1', 'WS|Samoa|685',
    'SM|San Marino|378', 'ST|São Tomé and Príncipe|239',
    'SA|Saudi Arabia|966', 'SN|Senegal|221', 'RS|Serbia|381',
    'SC|Seychelles|248', 'SL|Sierra Leone|232', 'SG|Singapore|65',
    'SK|Slovakia|421', 'SI|Slovenia|386', 'SB|Solomon Islands|677',
    'SO|Somalia|252', 'ZA|South Africa|27', 'KR|South Korea|82',
    'SS|South Sudan|211', 'ES|Spain|34', 'LK|Sri Lanka|94',
    'SD|Sudan|249', 'SR|Suriname|597', 'SE|Sweden|46',
    'CH|Switzerland|41', 'SY|Syria|963', 'TW|Taiwan|886',
    'TJ|Tajikistan|992', 'TZ|Tanzania|255', 'TH|Thailand|66',
    'TL|Timor-Leste|670', 'TG|Togo|228', 'TO|Tonga|676',
    'TT|Trinidad and Tobago|1', 'TN|Tunisia|216', 'TR|Turkey|90',
    'TM|Turkmenistan|993', 'TV|Tuvalu|688', 'UG|Uganda|256',
    'UA|Ukraine|380', 'AE|United Arab Emirates|971',
    'GB|United Kingdom|44', 'US|United States|1', 'UY|Uruguay|598',
    'UZ|Uzbekistan|998', 'VU|Vanuatu|678', 'VA|Vatican City|39',
    'VE|Venezuela|58', 'VN|Vietnam|84', 'YE|Yemen|967',
    'ZM|Zambia|260', 'ZW|Zimbabwe|263',
  ];
}

/// Opens the searchable country list. Returns the picked country, or null
/// if the sheet was dismissed.
Future<Country?> showCountryPicker(BuildContext context, {Country? selected}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CountryPickerSheet(selected: selected),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  final Country? selected;
  const _CountryPickerSheet({this.selected});

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  List<Country> get _filtered {
    final q = _query.trim().toLowerCase().replaceAll('+', '');
    if (q.isEmpty) return Country.all;
    return Country.all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.iso.toLowerCase() == q ||
          c.dial.startsWith(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final list = _filtered;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 14),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Choose your country', style: KaidoseBrand.display(20)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                cursorColor: KaidoseBrand.cyan,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search countries or codes',
                  prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                  filled: true,
                  fillColor: KaidoseBrand.fieldFill,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                child: Text('No countries match "$_query"',
                    style: TextStyle(color: Colors.grey[500])),
              )
                  : ListView.builder(
                keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final c = list[i];
                  final isSelected = c.iso == widget.selected?.iso;
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(c),
                    leading: Text(c.flag,
                        style: const TextStyle(fontSize: 24)),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: KaidoseBrand.ink,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('+${c.dial}',
                            style: TextStyle(
                                fontSize: 15, color: Colors.grey[600])),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.check,
                              size: 18, color: KaidoseBrand.cyan),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "🇺🇸 +1 ▾" button that sits at the left edge of a phone field.
/// Tapping it opens the country list.
class CountryCodeButton extends StatelessWidget {
  final Country country;
  final ValueChanged<Country> onChanged;

  const CountryCodeButton({
    Key? key,
    required this.country,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final picked = await showCountryPicker(context, selected: country);
        if (picked != null) onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text('+${country.dial}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: KaidoseBrand.ink)),
            Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 6),
            Container(width: 1, height: 22, color: Colors.grey[300]),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}