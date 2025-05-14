const decodeHex = (hex) => {
    const cleanHex = hex.replace(/\s/g, '');
    const bytes = Buffer.from(cleanHex, 'hex');
    return bytes.toString('utf8');
};

const decodeBase64 = (base64) => {
    const buffer = Buffer.from(base64, 'base64');
    try {
        return JSON.parse(buffer.toString('utf8'));
    } catch {
        return buffer.toString('utf8');
    }
};

const data = [
    {
        key: "000762616C616E6365636F736D6F733139667A7279746B636B636839633861753439636C6C6B707236346B3575706A327A7930797977",
        value: "Ijk5OTk5OTk4MDAwMCI="
    },
    {
        key: "000762616C616E6365636F736D6F733170753638663630396E7A39677637646135667379686A6735747035377575346476646D6E7577",
        value: "IjIwMDAwIg=="
    },
];

data.forEach((item, index) => {
    console.log(`\nEntry ${index + 1}:`);
    console.log('Decoded Key:', decodeHex(item.key));
    console.log('Decoded Value:', decodeBase64(item.value));
});
