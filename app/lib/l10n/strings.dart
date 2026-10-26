class Strings {
  Strings._();

  static const appName = 'uHribe';

  static const navPeaks = 'Vrhovi';
  static const navMap = 'Zemljevid';
  static const navProfile = 'Profil';
  static const navSettings = 'Nastavitve';

  static const loginTitle = 'Prijava';
  static const email = 'E-poštni naslov';
  static const password = 'Geslo';
  static const loginButton = 'Prijava';
  static const loginError = 'Napačen e-poštni naslov ali geslo.';
  static const loginGenericError = 'Prijava ni uspela. Poskusite znova.';
  static const logout = 'Odjava';

  static String greeting(String? name) {
    final trimmed = name?.trim() ?? '';
    final firstName = trimmed.split(RegExp(r'\s+')).first;
    return firstName.isEmpty ? 'Živijo!' : 'Živijo, $firstName!';
  }

  static const searchHint = 'Išči vrhove …';
  static const filterByArea = 'Gorovja';
  static const filterByElevation = 'Višina';
  static const allAreas = 'Vsa gorovja';
  static const allElevations = 'Vse višine';
  static const noPeaksFound = 'Ni najdenih vrhov.';
  static const clearFilters = 'Počisti filtre';

  static String peakCount(int shown, {required int of}) => shown == of ? '$of' : '$shown / $of';
  static const loadError = 'Napaka pri nalaganju podatkov.';
  static const retry = 'Poskusi znova';

  static const coordinates = 'Koordinate';
  static const wikipediaLink = 'Wikipedia';
  static const routesTitle = 'Planinske poti';
  static const noRoutes = 'Za ta vrh ni znanih poti.';
  static const alreadyVisited = 'Obiskano';
  static const save = 'Shrani';
  static const cancel = 'Prekliči';
  static const ok = 'V redu';
  static const visitDeleteError = 'Obiska ni bilo mogoče izbrisati.';

  static const checkIn = 'Osvojil sem vrh';
  static const checkInSearching = 'Iščem satelite …';
  static const checkInSearchingHint = 'Za natančno meritev ostanite na mestu nekaj sekund.';
  static const checkInRecorded = 'Vrh osvojen!';
  static const checkInQueued = 'Vrh osvojen. Čakanje na omrežje.';
  static const checkInTooFarTitle = 'Predaleč od vrha';
  static const checkInFailed = 'Prijave na vrh ni bilo mogoče izvesti.';
  static const checkInMocked =
      'Lokacija prihaja iz aplikacije za ponarejanje lokacije, prijave '
      'ni mogoče izvesti.';
  static const pendingBadge = 'Čakanje na sinhronizacijo';

  static String checkInTooFarBody(int distanceM, int allowedM) =>
      'Od vrha ste oddaljeni približno $distanceM m, prijava je mogoča le '
      'znotraj $allowedM m.';

  static const offline = 'Brez povezave';
  static const downloadForOffline = 'Prenesi za offline';
  static const downloadedForOffline = 'Na voljo offline';
  static const downloadFailed = 'Prenosa ni bilo mogoče dokončati.';
  static const routesOffline =
      'Poti za ta vrh niso prenesene. Prenesi jih, ko boš spet na omrežju.';
  static const discard = 'Zavrzi';
  static const rejectedCheckIn = 'Strežnik je vnos zavrnil';

  static const routeDifficulty = 'Zahtevnost';
  static const routeDistance = 'Dolžina';
  static const routeElevationGain = 'Višinska razlika';
  static const routeHighestPoint = 'Vrh';
  static const routeShow3d = 'Prikaži 3D relief';
  static const routeShow2d = 'Prikaži 2D zemljevid';

  static const displayName = 'Ime in priimek';
  static const homeRegion = 'Domača regija';
  static const changePhoto = 'Zamenjaj sliko';
  static const chooseFromGallery = 'Izberi iz galerije';
  static const takePhoto = 'Fotografiraj';
  static const avatarUploadError = 'Slike ni bilo mogoče naložiti.';
  static const editProfile = 'Uredi profil';
  static const profileSaved = 'Shranjeno';
  static const profileSaveError = 'Profila ni bilo mogoče shraniti.';

  static const settingsGeneral = 'Splošno';
  static const settingsGeneralSubtitle = 'Videz in lokacija';
  static const settingsAbout = 'O aplikaciji';
  static const appTagline = 'Beleženje obiskanih slovenskih vrhov.';
  static const dataSources = 'Viri podatkov';
  static const peakDataSource = 'Vrhovi in poti';
  static const mapDataSource = 'Zemljevid';
  static const copyright = '© 2026 uHribe. Vse pravice pridržane.';
  static const darkMode = 'Temni način';
  static const locationSetting = 'Dovoli uporabo lokacije';
  static const statsPeaksVisited = 'Obiskanih vrhov';
  static const statsTotalVisits = 'Vseh obiskov';
  static const statsThisYear = 'Letos';
  static const statsTotalElevation = 'Skupaj višine';
  static const statsHighestPeak = 'Najvišji vrh';
  static const statsFirstVisit = 'Prvi vzpon';
  static const statsLastVisit = 'Zadnji vzpon';
  static const statsTitle = 'Statistika';
  static const myVisits = 'Moji obiski';
  static const noVisitsYet = 'Dosegli niste še nobenega vrha.';
  static const deleteVisitConfirm = 'Izbrišem ta obisk?';
  static const delete = 'Izbriši';

  static const List<String> regions = [
    'Gorenjska',
    'Goriška',
    'Jugovzhodna Slovenija',
    'Koroška',
    'Obalno-kraška',
    'Osrednjeslovenska',
    'Podravska',
    'Pomurska',
    'Posavska',
    'Primorsko-notranjska',
    'Savinjska',
    'Zasavska',
  ];

  static const List<String> mountainAreas = [
    'Goriško, Notranjsko in Snežniško hribovje',
    'Julijske Alpe',
    'Kamniško Savinjske Alpe',
    'Karavanke',
    'Pohorje, Dravinjske gorice in Haloze',
    'Polhograjsko hribovje in Ljubljana',
    'Posavsko hribovje in Dolenjska',
    'Prekmurje',
    'Škofjeloško, Cerkljansko hribovje in Jelovica',
    'Strojna, Košenjak, Kozjak in Slovenske gorice',
  ];

  static const locationServicesDisabled =
      'Lokacijske storitve so izklopljene. Vklopite jih v nastavitvah naprave.';
  static const locationPermissionDenied =
      'Brez dovoljenja za lokacijo vam ne moremo pokazati, kje ste.';
  static const locationPermissionDeniedForever =
      'Dostop do lokacije je zavrnjen. Omogočite ga v nastavitvah aplikacije.';
  static const locationUnavailable = 'Vaše lokacije ni bilo mogoče določiti.';
  static const showMyLocation = 'Pokaži mojo lokacijo';
  static const showSatelliteMap = 'Satelitski prikaz';
  static const showOutdoorsMap = 'Zemljevid terena';
  static const resetNorth = 'Obrni proti severu';
  static const openSettings = 'Nastavitve';

  static const osmAttribution = '© OpenStreetMap contributors';
  static const mapboxAttribution = '© Mapbox';
}
