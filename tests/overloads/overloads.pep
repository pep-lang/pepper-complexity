# Overloads share a baseline line, and an extension of a generic type has
# a name with a space.
pick(x: int): int {
    if (x > 0) {
        return 1;
    }
    return 0;
}

pick(x: String): int {
    if (x.is_empty) {
        return 0;
    } else if (x == "a") {
        return 1;
    }
    return 2;
}

struct Pair<K, V> {
    var key: K;
    var value: V;
}

extend Pair<K, V> {
    keyed(): bool {
        return key !== __null ? true : false;
    }
}
