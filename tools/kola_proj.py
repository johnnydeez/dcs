"""Kola map projection: DCS projected metres <-> WGS84 lat/lon.

DCS terrains use a transverse Mercator projection on the WGS84 ellipsoid.
DCS coordinates are (x = northing, y = easting) in metres.

Kola parameters (from the terrain's own definition; also visible in pydcs's
dcs/terrain/kola/projection.py):
    central meridian 21 E, k0 = 0.9996,
    false easting  = -62702.0   (applied to easting  -> DCS y)
    false northing = -7543625.0 (applied to northing -> DCS x)

The maths is Karney's Krueger-series formulation ("Transverse Mercator with an
accuracy of a few nanometers", 2011), 6th order in n, which stays accurate
across the whole Kola map (~20 deg of longitude either side of the CM).

Only the standard library is used.
"""

import math

# WGS84
_A = 6378137.0
_F = 1.0 / 298.257223563

# Kola
CENTRAL_MERIDIAN = 21.0
SCALE_FACTOR = 0.9996
FALSE_EASTING = -62702.0
FALSE_NORTHING = -7543625.0

_N = _F / (2.0 - _F)
_E = math.sqrt(_F * (2.0 - _F))
_AA = _A / (1.0 + _N) * (1.0 + _N ** 2 / 4.0 + _N ** 4 / 64.0 + _N ** 6 / 256.0)

n = _N
_ALPHA = [
    n / 2 - 2 * n ** 2 / 3 + 5 * n ** 3 / 16 + 41 * n ** 4 / 180 - 127 * n ** 5 / 288 + 7891 * n ** 6 / 37800,
    13 * n ** 2 / 48 - 3 * n ** 3 / 5 + 557 * n ** 4 / 1440 + 281 * n ** 5 / 630 - 1983433 * n ** 6 / 1935360,
    61 * n ** 3 / 240 - 103 * n ** 4 / 140 + 15061 * n ** 5 / 26880 + 167603 * n ** 6 / 181440,
    49561 * n ** 4 / 161280 - 179 * n ** 5 / 168 + 6601661 * n ** 6 / 7257600,
    34729 * n ** 5 / 80640 - 3418889 * n ** 6 / 1995840,
    212378941 * n ** 6 / 319334400,
]
_BETA = [
    n / 2 - 2 * n ** 2 / 3 + 37 * n ** 3 / 96 - n ** 4 / 360 - 81 * n ** 5 / 512 + 96199 * n ** 6 / 604800,
    n ** 2 / 48 + n ** 3 / 15 - 437 * n ** 4 / 1440 + 46 * n ** 5 / 105 - 1118711 * n ** 6 / 3870720,
    17 * n ** 3 / 480 - 37 * n ** 4 / 840 - 209 * n ** 5 / 4480 + 5569 * n ** 6 / 90720,
    4397 * n ** 4 / 161280 - 11 * n ** 5 / 504 - 830251 * n ** 6 / 7257600,
    4583 * n ** 5 / 161280 - 108847 * n ** 6 / 3991680,
    20648693 * n ** 6 / 638668800,
]
del n


def _atanh(x):
    return 0.5 * math.log((1.0 + x) / (1.0 - x))


def to_latlon(x, y):
    """DCS (x=north, y=east) metres -> (lat, lon) degrees."""
    xi = (x - FALSE_NORTHING) / (SCALE_FACTOR * _AA)
    eta = (y - FALSE_EASTING) / (SCALE_FACTOR * _AA)

    xi_p, eta_p = xi, eta
    for j, b in enumerate(_BETA, start=1):
        xi_p -= b * math.sin(2 * j * xi) * math.cosh(2 * j * eta)
        eta_p -= b * math.cos(2 * j * xi) * math.sinh(2 * j * eta)

    sinh_eta = math.sinh(eta_p)
    cos_xi = math.cos(xi_p)
    tau_p = math.sin(xi_p) / math.sqrt(sinh_eta ** 2 + cos_xi ** 2)
    lon = math.atan2(sinh_eta, cos_xi)

    # Newton iteration: conformal latitude tau' -> geodetic tau = tan(phi)
    e2 = _E ** 2
    tau = tau_p
    for _ in range(10):
        sigma = math.sinh(_E * _atanh(_E * tau / math.sqrt(1.0 + tau ** 2)))
        tau_pi = tau * math.sqrt(1.0 + sigma ** 2) - sigma * math.sqrt(1.0 + tau ** 2)
        dtau = ((tau_p - tau_pi) * (1.0 + (1.0 - e2) * tau ** 2)
                / ((1.0 - e2) * math.sqrt(1.0 + tau_pi ** 2) * math.sqrt(1.0 + tau ** 2)))
        tau += dtau
        if abs(dtau) < 1e-14:
            break

    lat = math.degrees(math.atan(tau))
    lon = math.degrees(lon) + CENTRAL_MERIDIAN
    return lat, lon


def from_latlon(lat, lon):
    """(lat, lon) degrees -> DCS (x=north, y=east) metres."""
    phi = math.radians(lat)
    lam = math.radians(lon - CENTRAL_MERIDIAN)

    sin_phi = math.sin(phi)
    t = math.sinh(_atanh(sin_phi) - _E * _atanh(_E * sin_phi))
    xi_p = math.atan2(t, math.cos(lam))
    eta_p = _atanh(math.sin(lam) / math.sqrt(1.0 + t ** 2))

    xi, eta = xi_p, eta_p
    for j, a in enumerate(_ALPHA, start=1):
        xi += a * math.sin(2 * j * xi_p) * math.cosh(2 * j * eta_p)
        eta += a * math.cos(2 * j * xi_p) * math.sinh(2 * j * eta_p)

    x = SCALE_FACTOR * _AA * xi + FALSE_NORTHING
    y = SCALE_FACTOR * _AA * eta + FALSE_EASTING
    return x, y


def dist_m(ax, ay, bx, by):
    """Planar distance between two DCS points, metres (fine for nearest-base lookups)."""
    return math.hypot(bx - ax, by - ay)


def bearing_deg(ax, ay, bx, by):
    """Compass bearing from a to b, degrees (0 = north, 90 = east)."""
    d = math.degrees(math.atan2(by - ay, bx - ax))
    return d + 360.0 if d < 0 else d


def fmt_dms(lat, lon):
    """'N68°07'12"  E033°21'40"' — same layout the Syria Spawner.formatLL uses."""
    def dms(deg):
        a = abs(deg)
        d = int(a)
        m = int((a - d) * 60)
        s = int(((a - d) * 60 - m) * 60)
        return d, m, s
    la = dms(lat)
    lo = dms(lon)
    return '%s%d°%02d\'%02d"  %s%03d°%02d\'%02d"' % (
        "N" if lat >= 0 else "S", la[0], la[1], la[2],
        "E" if lon >= 0 else "W", lo[0], lo[1], lo[2])


if __name__ == "__main__":
    # Round-trip + sanity check against published airport coordinates.
    checks = [
        ("Banak",        234846.247614,  88378.912238, 70.0687, 24.9735),
        ("Rovaniemi",   -152462.09375,  151503.710938, 66.5648, 25.8304),
        ("Murmansk Intl", 131730.496094, 409479.0,     68.7817, 32.7508),
        ("Bodo",         -66958.882813, -348337.328125, 67.2692, 14.3653),
    ]
    for name, x, y, lat_ref, lon_ref in checks:
        lat, lon = to_latlon(x, y)
        rx, ry = from_latlon(lat, lon)
        print("%-14s %9.4f %9.4f  (ref %8.4f %8.4f)  d=%.2fkm  roundtrip err %.3fm" % (
            name, lat, lon, lat_ref, lon_ref,
            dist_m(*from_latlon(lat_ref, lon_ref), x, y) / 1000.0,
            dist_m(x, y, rx, ry)))
