-- Reference data: countries (ISO 3166-1 alpha-2), the provinces, territories and emirates of
-- Pakistan and the United Arab Emirates (ISO 3166-2 codes), and their main cities.
-- Safe to run any number of times: only missing rows are added; names of existing codes are kept.
SET NOCOUNT ON;

DECLARE @countries TABLE (iso_code CHAR(2) PRIMARY KEY, name NVARCHAR(200));
INSERT @countries (iso_code, name) VALUES
    ('AF', N'Afghanistan'), ('AX', N'Åland Islands'), ('AL', N'Albania'), ('DZ', N'Algeria'), ('AS', N'American Samoa'),
    ('AD', N'Andorra'), ('AO', N'Angola'), ('AI', N'Anguilla'), ('AQ', N'Antarctica'), ('AG', N'Antigua and Barbuda'),
    ('AR', N'Argentina'), ('AM', N'Armenia'), ('AW', N'Aruba'), ('AU', N'Australia'), ('AT', N'Austria'),
    ('AZ', N'Azerbaijan'), ('BS', N'Bahamas'), ('BH', N'Bahrain'), ('BD', N'Bangladesh'), ('BB', N'Barbados'),
    ('BY', N'Belarus'), ('BE', N'Belgium'), ('BZ', N'Belize'), ('BJ', N'Benin'), ('BM', N'Bermuda'),
    ('BT', N'Bhutan'), ('BO', N'Bolivia'), ('BQ', N'Bonaire, Sint Eustatius and Saba'), ('BA', N'Bosnia and Herzegovina'),
    ('BW', N'Botswana'), ('BV', N'Bouvet Island'), ('BR', N'Brazil'), ('IO', N'British Indian Ocean Territory'),
    ('BN', N'Brunei Darussalam'), ('BG', N'Bulgaria'), ('BF', N'Burkina Faso'), ('BI', N'Burundi'), ('CV', N'Cabo Verde'),
    ('KH', N'Cambodia'), ('CM', N'Cameroon'), ('CA', N'Canada'), ('KY', N'Cayman Islands'), ('CF', N'Central African Republic'),
    ('TD', N'Chad'), ('CL', N'Chile'), ('CN', N'China'), ('CX', N'Christmas Island'), ('CC', N'Cocos (Keeling) Islands'),
    ('CO', N'Colombia'), ('KM', N'Comoros'), ('CG', N'Congo'), ('CD', N'Congo, Democratic Republic of the'),
    ('CK', N'Cook Islands'), ('CR', N'Costa Rica'), ('CI', N'Côte d''Ivoire'), ('HR', N'Croatia'), ('CU', N'Cuba'),
    ('CW', N'Curaçao'), ('CY', N'Cyprus'), ('CZ', N'Czechia'), ('DK', N'Denmark'), ('DJ', N'Djibouti'), ('DM', N'Dominica'),
    ('DO', N'Dominican Republic'), ('EC', N'Ecuador'), ('EG', N'Egypt'), ('SV', N'El Salvador'), ('GQ', N'Equatorial Guinea'),
    ('ER', N'Eritrea'), ('EE', N'Estonia'), ('SZ', N'Eswatini'), ('ET', N'Ethiopia'), ('FK', N'Falkland Islands (Malvinas)'),
    ('FO', N'Faroe Islands'), ('FJ', N'Fiji'), ('FI', N'Finland'), ('FR', N'France'), ('GF', N'French Guiana'),
    ('PF', N'French Polynesia'), ('TF', N'French Southern Territories'), ('GA', N'Gabon'), ('GM', N'Gambia'), ('GE', N'Georgia'),
    ('DE', N'Germany'), ('GH', N'Ghana'), ('GI', N'Gibraltar'), ('GR', N'Greece'), ('GL', N'Greenland'), ('GD', N'Grenada'),
    ('GP', N'Guadeloupe'), ('GU', N'Guam'), ('GT', N'Guatemala'), ('GG', N'Guernsey'), ('GN', N'Guinea'),
    ('GW', N'Guinea-Bissau'), ('GY', N'Guyana'), ('HT', N'Haiti'), ('HM', N'Heard Island and McDonald Islands'),
    ('VA', N'Holy See'), ('HN', N'Honduras'), ('HK', N'Hong Kong'), ('HU', N'Hungary'), ('IS', N'Iceland'), ('IN', N'India'),
    ('ID', N'Indonesia'), ('IR', N'Iran'), ('IQ', N'Iraq'), ('IE', N'Ireland'), ('IM', N'Isle of Man'), ('IL', N'Israel'),
    ('IT', N'Italy'), ('JM', N'Jamaica'), ('JP', N'Japan'), ('JE', N'Jersey'), ('JO', N'Jordan'), ('KZ', N'Kazakhstan'),
    ('KE', N'Kenya'), ('KI', N'Kiribati'), ('KP', N'Korea, Democratic People''s Republic of'), ('KR', N'Korea, Republic of'),
    ('KW', N'Kuwait'), ('KG', N'Kyrgyzstan'), ('LA', N'Lao People''s Democratic Republic'), ('LV', N'Latvia'),
    ('LB', N'Lebanon'), ('LS', N'Lesotho'), ('LR', N'Liberia'), ('LY', N'Libya'), ('LI', N'Liechtenstein'),
    ('LT', N'Lithuania'), ('LU', N'Luxembourg'), ('MO', N'Macao'), ('MG', N'Madagascar'), ('MW', N'Malawi'),
    ('MY', N'Malaysia'), ('MV', N'Maldives'), ('ML', N'Mali'), ('MT', N'Malta'), ('MH', N'Marshall Islands'),
    ('MQ', N'Martinique'), ('MR', N'Mauritania'), ('MU', N'Mauritius'), ('YT', N'Mayotte'), ('MX', N'Mexico'),
    ('FM', N'Micronesia'), ('MD', N'Moldova'), ('MC', N'Monaco'), ('MN', N'Mongolia'), ('ME', N'Montenegro'),
    ('MS', N'Montserrat'), ('MA', N'Morocco'), ('MZ', N'Mozambique'), ('MM', N'Myanmar'), ('NA', N'Namibia'),
    ('NR', N'Nauru'), ('NP', N'Nepal'), ('NL', N'Netherlands'), ('NC', N'New Caledonia'), ('NZ', N'New Zealand'),
    ('NI', N'Nicaragua'), ('NE', N'Niger'), ('NG', N'Nigeria'), ('NU', N'Niue'), ('NF', N'Norfolk Island'),
    ('MK', N'North Macedonia'), ('MP', N'Northern Mariana Islands'), ('NO', N'Norway'), ('OM', N'Oman'), ('PK', N'Pakistan'),
    ('PW', N'Palau'), ('PS', N'Palestine, State of'), ('PA', N'Panama'), ('PG', N'Papua New Guinea'), ('PY', N'Paraguay'),
    ('PE', N'Peru'), ('PH', N'Philippines'), ('PN', N'Pitcairn'), ('PL', N'Poland'), ('PT', N'Portugal'),
    ('PR', N'Puerto Rico'), ('QA', N'Qatar'), ('RE', N'Réunion'), ('RO', N'Romania'), ('RU', N'Russian Federation'),
    ('RW', N'Rwanda'), ('BL', N'Saint Barthélemy'), ('SH', N'Saint Helena, Ascension and Tristan da Cunha'),
    ('KN', N'Saint Kitts and Nevis'), ('LC', N'Saint Lucia'), ('MF', N'Saint Martin (French part)'),
    ('PM', N'Saint Pierre and Miquelon'), ('VC', N'Saint Vincent and the Grenadines'), ('WS', N'Samoa'),
    ('SM', N'San Marino'), ('ST', N'Sao Tome and Principe'), ('SA', N'Saudi Arabia'), ('SN', N'Senegal'), ('RS', N'Serbia'),
    ('SC', N'Seychelles'), ('SL', N'Sierra Leone'), ('SG', N'Singapore'), ('SX', N'Sint Maarten (Dutch part)'),
    ('SK', N'Slovakia'), ('SI', N'Slovenia'), ('SB', N'Solomon Islands'), ('SO', N'Somalia'), ('ZA', N'South Africa'),
    ('GS', N'South Georgia and the South Sandwich Islands'), ('SS', N'South Sudan'), ('ES', N'Spain'), ('LK', N'Sri Lanka'),
    ('SD', N'Sudan'), ('SR', N'Suriname'), ('SJ', N'Svalbard and Jan Mayen'), ('SE', N'Sweden'), ('CH', N'Switzerland'),
    ('SY', N'Syrian Arab Republic'), ('TW', N'Taiwan'), ('TJ', N'Tajikistan'), ('TZ', N'Tanzania'), ('TH', N'Thailand'),
    ('TL', N'Timor-Leste'), ('TG', N'Togo'), ('TK', N'Tokelau'), ('TO', N'Tonga'), ('TT', N'Trinidad and Tobago'),
    ('TN', N'Tunisia'), ('TR', N'Türkiye'), ('TM', N'Turkmenistan'), ('TC', N'Turks and Caicos Islands'), ('TV', N'Tuvalu'),
    ('UG', N'Uganda'), ('UA', N'Ukraine'), ('AE', N'United Arab Emirates'), ('GB', N'United Kingdom'),
    ('US', N'United States'), ('UM', N'United States Minor Outlying Islands'), ('UY', N'Uruguay'), ('UZ', N'Uzbekistan'),
    ('VU', N'Vanuatu'), ('VE', N'Venezuela'), ('VN', N'Viet Nam'), ('VG', N'Virgin Islands (British)'),
    ('VI', N'Virgin Islands (U.S.)'), ('WF', N'Wallis and Futuna'), ('EH', N'Western Sahara'), ('YE', N'Yemen'),
    ('ZM', N'Zambia'), ('ZW', N'Zimbabwe');

INSERT [org].[country] (iso_code, name)
SELECT c.iso_code, c.name
FROM @countries c
WHERE NOT EXISTS (SELECT 1 FROM [org].[country] x WHERE x.iso_code = c.iso_code);

DECLARE @states TABLE (code NVARCHAR(30) PRIMARY KEY, country_code CHAR(2), name NVARCHAR(200));
INSERT @states (code, country_code, name) VALUES
    (N'PK-PB', 'PK', N'Punjab'), (N'PK-SD', 'PK', N'Sindh'), (N'PK-KP', 'PK', N'Khyber Pakhtunkhwa'),
    (N'PK-BA', 'PK', N'Balochistan'), (N'PK-IS', 'PK', N'Islamabad Capital Territory'),
    (N'PK-GB', 'PK', N'Gilgit-Baltistan'), (N'PK-JK', 'PK', N'Azad Jammu and Kashmir'),
    (N'AE-AZ', 'AE', N'Abu Dhabi'), (N'AE-DU', 'AE', N'Dubai'), (N'AE-SH', 'AE', N'Sharjah'), (N'AE-AJ', 'AE', N'Ajman'),
    (N'AE-UQ', 'AE', N'Umm Al Quwain'), (N'AE-RK', 'AE', N'Ras Al Khaimah'), (N'AE-FU', 'AE', N'Fujairah');

INSERT [org].[state] (country_id, code, name)
SELECT c.id, s.code, s.name
FROM @states s
JOIN [org].[country] c ON c.iso_code = s.country_code
WHERE NOT EXISTS (SELECT 1 FROM [org].[state] x WHERE x.code = s.code);

DECLARE @cities TABLE (state_code NVARCHAR(30), name NVARCHAR(200));
INSERT @cities (state_code, name) VALUES
    (N'PK-PB', N'Lahore'), (N'PK-PB', N'Faisalabad'), (N'PK-PB', N'Rawalpindi'), (N'PK-PB', N'Multan'),
    (N'PK-PB', N'Gujranwala'), (N'PK-PB', N'Sialkot'), (N'PK-PB', N'Bahawalpur'), (N'PK-PB', N'Sargodha'),
    (N'PK-PB', N'Sheikhupura'), (N'PK-PB', N'Gujrat'), (N'PK-PB', N'Sahiwal'), (N'PK-PB', N'Rahim Yar Khan'),
    (N'PK-PB', N'Jhang'), (N'PK-PB', N'Dera Ghazi Khan'), (N'PK-PB', N'Kasur'), (N'PK-PB', N'Okara'),
    (N'PK-SD', N'Karachi'), (N'PK-SD', N'Hyderabad'), (N'PK-SD', N'Sukkur'), (N'PK-SD', N'Larkana'),
    (N'PK-SD', N'Nawabshah'), (N'PK-SD', N'Mirpur Khas'), (N'PK-SD', N'Jacobabad'), (N'PK-SD', N'Thatta'),
    (N'PK-KP', N'Peshawar'), (N'PK-KP', N'Mardan'), (N'PK-KP', N'Abbottabad'), (N'PK-KP', N'Mingora'),
    (N'PK-KP', N'Kohat'), (N'PK-KP', N'Dera Ismail Khan'), (N'PK-KP', N'Bannu'), (N'PK-KP', N'Mansehra'),
    (N'PK-KP', N'Nowshera'),
    (N'PK-BA', N'Quetta'), (N'PK-BA', N'Gwadar'), (N'PK-BA', N'Turbat'), (N'PK-BA', N'Khuzdar'), (N'PK-BA', N'Sibi'),
    (N'PK-BA', N'Chaman'),
    (N'PK-IS', N'Islamabad'),
    (N'PK-GB', N'Gilgit'), (N'PK-GB', N'Skardu'), (N'PK-GB', N'Hunza'),
    (N'PK-JK', N'Muzaffarabad'), (N'PK-JK', N'Mirpur'), (N'PK-JK', N'Rawalakot'), (N'PK-JK', N'Kotli'),
    (N'AE-AZ', N'Abu Dhabi'), (N'AE-AZ', N'Al Ain'), (N'AE-AZ', N'Madinat Zayed'),
    (N'AE-DU', N'Dubai'), (N'AE-DU', N'Hatta'),
    (N'AE-SH', N'Sharjah'), (N'AE-SH', N'Khor Fakkan'), (N'AE-SH', N'Kalba'),
    (N'AE-AJ', N'Ajman'), (N'AE-UQ', N'Umm Al Quwain'), (N'AE-RK', N'Ras Al Khaimah'),
    (N'AE-FU', N'Fujairah'), (N'AE-FU', N'Dibba Al-Fujairah');

INSERT [org].[city] (state_id, name)
SELECT s.id, c.name
FROM @cities c
JOIN [org].[state] s ON s.code = c.state_code
WHERE NOT EXISTS (SELECT 1 FROM [org].[city] x WHERE x.state_id = s.id AND x.name = c.name);
