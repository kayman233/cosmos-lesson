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
        key: "000762616C616E6365636F736D6F733139377361793373776337753461746E36746B3665786E3379367568767A6C6C337A6166673666",
        value: "IjEwMDAwIg=="
    },
    {
        key: "000762616C616E6365636F736D6F73316A7A6D336E7A6A616A6432656C6364653933763271747A657378736A73676C703074676A7432",
        value: "Ijk5OTk5OTk5MDAwMCI="
    },
];

data.forEach((item, index) => {
    console.log(`\nEntry ${index + 1}:`);
    console.log('Decoded Key:', decodeHex(item.key));
    console.log('Decoded Value:', decodeBase64(item.value));
});
