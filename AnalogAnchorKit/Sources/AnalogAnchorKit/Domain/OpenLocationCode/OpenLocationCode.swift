// Copyright 2014 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Ported to Swift for Analog Anchor (iOS) from the existing Android
// `OpenLocationCode.java`. Logic and constants are preserved 1:1.

import Foundation

/// Convert locations to and from convenient short codes (Plus Codes).
public final class OpenLocationCode {

    /// Normal precision code (~14x14 m).
    public static let codePrecisionNormal = 10

    /// Character set used to encode values.
    public static let codeAlphabet = "23456789CFGHJMPQRVWX"

    /// Separator used to break the code into two parts.
    public static let separator: Character = "+"

    /// Character used to pad codes.
    public static let paddingCharacter: Character = "0"

    private static let separatorPosition = 8
    public static let minDigitCount = 2
    public static let maxDigitCount = 15
    private static let pairCodeLength = 10
    private static let gridCodeLength = maxDigitCount - pairCodeLength
    private static let encodingBase = codeAlphabet.count
    private static let latitudeMax: Int64 = 90
    private static let longitudeMax: Int64 = 180
    private static let gridColumns = 4
    private static let gridRows = 5
    private static let latIntegerMultiplier: Int64 = 8000 * 3125
    private static let lngIntegerMultiplier: Int64 = 8000 * 1024
    private static let latMspValue = latIntegerMultiplier * Int64(encodingBase) * Int64(encodingBase)
    private static let lngMspValue = lngIntegerMultiplier * Int64(encodingBase) * Int64(encodingBase)

    private static let alphabetChars = Array(codeAlphabet)

    private static func alphabetIndex(_ c: Character) -> Int? {
        alphabetChars.firstIndex(of: c)
    }

    /// Coordinates of a decoded Open Location Code.
    public struct CodeArea: Equatable {
        public let southLatitude: Double
        public let westLongitude: Double
        public let northLatitude: Double
        public let eastLongitude: Double
        public let length: Int

        public var latitudeHeight: Double { northLatitude - southLatitude }
        public var longitudeWidth: Double { eastLongitude - westLongitude }
        public var centerLatitude: Double { (southLatitude + northLatitude) / 2 }
        public var centerLongitude: Double { (westLongitude + eastLongitude) / 2 }
    }

    public enum OLCError: Error {
        case invalidCode(String)
        case illegalCodeLength(Int)
        case notFullCode(String)
        case notShortenFull
        case paddedCode
        case referenceTooFar
        case decodeRequiresFullCode(String)
    }

    private let code: String

    /// Creates an OpenLocationCode from an existing (full or short) code string.
    public init(_ code: String) throws {
        let upper = code.uppercased()
        guard OpenLocationCode.isValidCode(upper) else {
            throw OLCError.invalidCode(code)
        }
        self.code = upper
    }

    /// Creates an OpenLocationCode from a coordinate and desired length.
    public init(latitude: Double, longitude: Double, codeLength: Int = OpenLocationCode.codePrecisionNormal) throws {
        let ints = OpenLocationCode.degreesToIntegers(latitude, longitude)
        self.code = try OpenLocationCode.encodeIntegers(ints.0, ints.1, codeLength)
    }

    public var string: String { code }

    // MARK: - Encoding

    static func encodeIntegers(_ latIn: Int64, _ lngIn: Int64, _ codeLengthIn: Int) throws -> String {
        let codeLength = min(codeLengthIn, maxDigitCount)
        if (codeLength < pairCodeLength && codeLength % 2 == 1) || codeLength < minDigitCount {
            throw OLCError.illegalCodeLength(codeLength)
        }
        var lat = latIn
        var lng = lngIn

        var rev = [Character]()
        if codeLength > pairCodeLength {
            for _ in 0..<gridCodeLength {
                let latDigit = lat % Int64(gridRows)
                let lngDigit = lng % Int64(gridColumns)
                let ndx = Int(latDigit * Int64(gridColumns) + lngDigit)
                rev.append(alphabetChars[ndx])
                lat /= Int64(gridRows)
                lng /= Int64(gridColumns)
            }
        } else {
            lat = Int64(Double(lat) / pow(Double(gridRows), Double(gridCodeLength)))
            lng = Int64(Double(lng) / pow(Double(gridColumns), Double(gridCodeLength)))
        }
        for i in 0..<(pairCodeLength / 2) {
            rev.append(alphabetChars[Int(lng % Int64(encodingBase))])
            rev.append(alphabetChars[Int(lat % Int64(encodingBase))])
            lat /= Int64(encodingBase)
            lng /= Int64(encodingBase)
            if i == 0 { rev.append(separator) }
        }
        var codeChars = Array(rev.reversed())

        if codeLength < separatorPosition {
            for i in codeLength..<separatorPosition {
                codeChars[i] = paddingCharacter
            }
        }
        let end = max(separatorPosition + 1, codeLength + 1)
        return String(codeChars[0..<end])
    }

    public static func encode(latitude: Double, longitude: Double) throws -> String {
        try OpenLocationCode(latitude: latitude, longitude: longitude).string
    }

    public static func encode(latitude: Double, longitude: Double, codeLength: Int) throws -> String {
        try OpenLocationCode(latitude: latitude, longitude: longitude, codeLength: codeLength).string
    }

    // MARK: - Decoding

    public func decode() throws -> CodeArea {
        guard isFull else {
            throw OLCError.decodeRequiresFullCode(code)
        }
        let clean = code.replacingOccurrences(of: String(OpenLocationCode.separator), with: "")
            .replacingOccurrences(of: String(OpenLocationCode.paddingCharacter), with: "")
        let cleanChars = Array(clean)

        var latVal = -OpenLocationCode.latitudeMax * OpenLocationCode.latIntegerMultiplier
        var lngVal = -OpenLocationCode.longitudeMax * OpenLocationCode.lngIntegerMultiplier
        var latPlaceVal = OpenLocationCode.latMspValue
        var lngPlaceVal = OpenLocationCode.lngMspValue

        let pairLimit = min(cleanChars.count, OpenLocationCode.pairCodeLength)
        var i = 0
        while i < pairLimit {
            latPlaceVal /= Int64(OpenLocationCode.encodingBase)
            lngPlaceVal /= Int64(OpenLocationCode.encodingBase)
            latVal += Int64(OpenLocationCode.alphabetIndex(cleanChars[i]) ?? 0) * latPlaceVal
            lngVal += Int64(OpenLocationCode.alphabetIndex(cleanChars[i + 1]) ?? 0) * lngPlaceVal
            i += 2
        }
        if OpenLocationCode.pairCodeLength < cleanChars.count {
            for j in OpenLocationCode.pairCodeLength..<min(cleanChars.count, OpenLocationCode.maxDigitCount) {
                latPlaceVal /= Int64(OpenLocationCode.gridRows)
                lngPlaceVal /= Int64(OpenLocationCode.gridColumns)
                let digit = OpenLocationCode.alphabetIndex(cleanChars[j]) ?? 0
                let row = digit / OpenLocationCode.gridColumns
                let col = digit % OpenLocationCode.gridColumns
                latVal += Int64(row) * latPlaceVal
                lngVal += Int64(col) * lngPlaceVal
            }
        }

        let latitudeLo = Double(latVal) / Double(OpenLocationCode.latIntegerMultiplier)
        let longitudeLo = Double(lngVal) / Double(OpenLocationCode.lngIntegerMultiplier)
        let latitudeHi = Double(latVal + latPlaceVal) / Double(OpenLocationCode.latIntegerMultiplier)
        let longitudeHi = Double(lngVal + lngPlaceVal) / Double(OpenLocationCode.lngIntegerMultiplier)

        return CodeArea(
            southLatitude: latitudeLo,
            westLongitude: longitudeLo,
            northLatitude: latitudeHi,
            eastLongitude: longitudeHi,
            length: min(cleanChars.count, OpenLocationCode.maxDigitCount)
        )
    }

    public static func decode(_ code: String) throws -> CodeArea {
        try OpenLocationCode(code).decode()
    }

    // MARK: - Full / short / padded

    public var isFull: Bool {
        code.firstIndex(of: OpenLocationCode.separator).map { code.distance(from: code.startIndex, to: $0) == OpenLocationCode.separatorPosition } ?? false
    }

    public var isShort: Bool {
        guard let idx = code.firstIndex(of: OpenLocationCode.separator) else { return false }
        let pos = code.distance(from: code.startIndex, to: idx)
        return pos >= 0 && pos < OpenLocationCode.separatorPosition
    }

    private var isPadded: Bool {
        code.contains(OpenLocationCode.paddingCharacter)
    }

    // MARK: - Shorten / recover

    public func shorten(referenceLatitude: Double, referenceLongitude: Double) throws -> OpenLocationCode {
        guard isFull else { throw OLCError.notShortenFull }
        guard !isPadded else { throw OLCError.paddedCode }

        let area = try decode()
        let range = max(
            abs(referenceLatitude - area.centerLatitude),
            abs(referenceLongitude - area.centerLongitude)
        )
        for i in stride(from: 4, through: 1, by: -1) {
            if range < (OpenLocationCode.computeLatitudePrecision(i * 2) * 0.3) {
                let idx = code.index(code.startIndex, offsetBy: i * 2)
                return try OpenLocationCode(String(code[idx...]))
            }
        }
        throw OLCError.referenceTooFar
    }

    public func recover(referenceLatitude: Double, referenceLongitude: Double) throws -> OpenLocationCode {
        if isFull { return self }
        let refLat = OpenLocationCode.clipLatitude(referenceLatitude)
        let refLng = OpenLocationCode.normalizeLongitude(referenceLongitude)

        let sepIndex = code.firstIndex(of: OpenLocationCode.separator)
            .map { code.distance(from: code.startIndex, to: $0) } ?? 0
        let digitsToRecover = OpenLocationCode.separatorPosition - sepIndex
        let prefixPrecision = pow(Double(OpenLocationCode.encodingBase), Double(2 - (digitsToRecover / 2)))

        let refCode = try OpenLocationCode(latitude: refLat, longitude: refLng).string
        let refPrefix = String(refCode.prefix(digitsToRecover))
        let recovered = try OpenLocationCode(refPrefix + code)
        let recoveredArea = try recovered.decode()

        var recoveredLatitude = recoveredArea.centerLatitude
        var recoveredLongitude = recoveredArea.centerLongitude

        let latitudeDiff = recoveredLatitude - refLat
        if latitudeDiff > prefixPrecision / 2 && recoveredLatitude - prefixPrecision > -Double(OpenLocationCode.latitudeMax) {
            recoveredLatitude -= prefixPrecision
        } else if latitudeDiff < -prefixPrecision / 2 && recoveredLatitude + prefixPrecision < Double(OpenLocationCode.latitudeMax) {
            recoveredLatitude += prefixPrecision
        }

        let longitudeDiff = recoveredArea.centerLongitude - refLng
        if longitudeDiff > prefixPrecision / 2 {
            recoveredLongitude -= prefixPrecision
        } else if longitudeDiff < -prefixPrecision / 2 {
            recoveredLongitude += prefixPrecision
        }

        return try OpenLocationCode(latitude: recoveredLatitude, longitude: recoveredLongitude, codeLength: recovered.code.count - 1)
    }

    public func contains(latitude: Double, longitude: Double) throws -> Bool {
        let area = try decode()
        return area.southLatitude <= latitude && latitude < area.northLatitude
            && area.westLongitude <= longitude && longitude < area.eastLongitude
    }

    // MARK: - Validation

    public static func isValidCode(_ codeIn: String) -> Bool {
        guard codeIn.count >= 2 else { return false }
        let code = codeIn.uppercased()
        let chars = Array(code)

        guard let sepIndex = chars.firstIndex(of: separator) else { return false }
        if chars.lastIndex(of: separator) != sepIndex { return false }
        if sepIndex % 2 != 0 || sepIndex > separatorPosition { return false }

        if sepIndex == separatorPosition {
            if (alphabetIndex(chars[0]) ?? -1) > 8 { return false }
            if (alphabetIndex(chars[1]) ?? -1) > 17 { return false }
        }

        var paddingStarted = false
        var i = 0
        while i < sepIndex {
            if alphabetIndex(chars[i]) == nil && chars[i] != paddingCharacter { return false }
            if paddingStarted {
                if chars[i] != paddingCharacter { return false }
            } else if chars[i] == paddingCharacter {
                paddingStarted = true
                if sepIndex < separatorPosition { return false }
                if i != 2 && i != 4 && i != 6 { return false }
            }
            i += 1
        }

        if chars.count > sepIndex + 1 {
            if paddingStarted { return false }
            if chars.count == sepIndex + 2 { return false }
            var j = sepIndex + 1
            while j < chars.count {
                if alphabetIndex(chars[j]) == nil { return false }
                j += 1
            }
        }
        return true
    }

    public static func isFullCode(_ code: String) -> Bool {
        (try? OpenLocationCode(code).isFull) ?? false
    }

    public static func isShortCode(_ code: String) -> Bool {
        (try? OpenLocationCode(code).isShort) ?? false
    }

    // MARK: - Private helpers

    static func degreesToIntegers(_ latitude: Double, _ longitude: Double) -> (Int64, Int64) {
        var lat = Int64(floor(latitude * Double(latIntegerMultiplier)))
        var lng = Int64(floor(longitude * Double(lngIntegerMultiplier)))

        lat += latitudeMax * latIntegerMultiplier
        if lat < 0 {
            lat = 0
        } else if lat >= 2 * latitudeMax * latIntegerMultiplier {
            lat = 2 * latitudeMax * latIntegerMultiplier - 1
        }
        lng += longitudeMax * lngIntegerMultiplier
        if lng < 0 {
            lng = lng % (2 * longitudeMax * lngIntegerMultiplier) + 2 * longitudeMax * lngIntegerMultiplier
        } else if lng >= 2 * longitudeMax * lngIntegerMultiplier {
            lng = lng % (2 * longitudeMax * lngIntegerMultiplier)
        }
        return (lat, lng)
    }

    private static func clipLatitude(_ latitude: Double) -> Double {
        min(max(latitude, -Double(latitudeMax)), Double(latitudeMax))
    }

    private static func normalizeLongitude(_ longitude: Double) -> Double {
        if longitude >= -Double(longitudeMax) && longitude < Double(longitudeMax) {
            return longitude
        }
        let circleDeg: Double = 2 * Double(longitudeMax)
        return (longitude.truncatingRemainder(dividingBy: circleDeg) + circleDeg + Double(longitudeMax))
            .truncatingRemainder(dividingBy: circleDeg) - Double(longitudeMax)
    }

    private static func computeLatitudePrecision(_ codeLength: Int) -> Double {
        if codeLength <= codePrecisionNormal {
            return pow(Double(encodingBase), Double(codeLength / -2 + 2))
        }
        return pow(Double(encodingBase), -3.0) / pow(Double(gridRows), Double(codeLength - pairCodeLength))
    }
}
