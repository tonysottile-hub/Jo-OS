const {test}=require('node:test');const assert=require('node:assert/strict');const {permitted}=require('./policy.cjs');
test('only approved read-only destinations',()=>{
 assert.equal(permitted('https://cigar30-shop.fourthwall.com/products/a-shirt'),true);
 for(const u of ['http://cigar30-shop.fourthwall.com/','https://cigar30-shop.fourthwall.com.evil.test/','https://127.0.0.1/','file:///etc/passwd','https://cigar30-shop.fourthwall.com/?token=secret','https://cigar30-shop.fourthwall.com/checkout','https://user:pass@cigar30-shop.fourthwall.com/','https://cigar30-shop.fourthwall.com/download.zip'])assert.equal(permitted(u),false,u);
 assert.equal(permitted('https://cigar30-shop.fourthwall.com/','POST'),false);
 assert.equal(permitted('https://cigar30-shop.fourthwall.com/','GET','script'),false);
});
