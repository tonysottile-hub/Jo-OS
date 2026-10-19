"""Independent geographic checks for rendered media provenance."""
import re

def required_terms_match(sources, required_terms):
    terms = [str(term).strip() for term in required_terms if str(term).strip()]
    if not sources or not terms:
        return False
    for source in sources:
        # Artist/credit/query strings do not prove where an image was taken.
        text = ' '.join(str(source.get(key, '')) for key in
                        ('title', 'description', 'categories', 'location'))
        if not all(re.search(r'\b' + re.escape(term) + r'\b', text, re.I)
                   for term in terms):
            return False
    return True

def unique_source_count(sources):
    """Crops and renamed titles are not additional source images."""
    return len({str(s.get('source_url') or s.get('url') or '').strip()
                for s in sources} - {''})
