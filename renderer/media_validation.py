"""Independent geographic checks for rendered media provenance."""
import re

def required_terms_match(sources, required_terms):
    terms = [str(term).strip() for term in required_terms if str(term).strip()]
    if not sources:
        return False
    for source in sources:
        # Artist/credit/query strings do not prove where an image was taken.
        text = ' '.join(str(source.get(key, '')) for key in
                        ('title', 'description', 'categories', 'location'))
        if not all(re.search(r'\b' + re.escape(term) + r'\b', text, re.I)
                   for term in terms):
            return False
    return True
