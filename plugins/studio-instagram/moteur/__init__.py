"""Moteur du Studio Instagram (scripts appelés par Claude via ./studio)."""
import warnings

# Le Python livré avec macOS utilise LibreSSL : urllib3 le signale à chaque appel, sans conséquence ici.
warnings.filterwarnings("ignore", message=".*urllib3 v2 only supports OpenSSL.*")

__version__ = "1.0.0"
