import XCTest
@testable import Tendedero

/// The proof of time: the question for a time stamp, and what is read from
/// real answers, kept from Sectigo's qualified authority and from Free TSA,
/// both to the question below.
final class TrustedTimeTests: XCTestCase {
    /// The fingerprint asked about: the bytes 0 to 31.
    private let fingerprint = Data((0..<32).map { UInt8($0) })
    private let nonce = Data([0x8A, 1, 2, 3, 4, 5, 6, 7])

    func testTheQuestionIsAnRFC3161Request() {
        let query = [UInt8](TrustedTime.query(sha256: fingerprint, nonce: nonce))
        // SEQUENCE, version 1, SHA-256 with no parameters, the fingerprint,
        // the random number (with a zero in front, as its first bit is set)
        // and a request for the certificate.
        let expected: [UInt8] = [0x30, 0x44, 0x02, 0x01, 0x01, 0x30, 0x31, 0x30, 0x0D,
                                 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00,
                                 0x04, 0x20] + [UInt8](fingerprint)
            + [0x02, 0x09, 0x00, 0x8A, 1, 2, 3, 4, 5, 6, 7, 0x01, 0x01, 0xFF]
        XCTAssertEqual(query, expected)
    }

    func testAQualifiedAnswerIsRead() throws {
        let stamp = try TrustedTime.stamp(from: sectigo, sha256: fingerprint, nonce: nonce)
        XCTAssertEqual(stamp.time, Date(timeIntervalSince1970: 1795782912))
        XCTAssertEqual(stamp.accuracy, 1)
        XCTAssertEqual(stamp.serial, "EA6BC1B49B7C437A32C88E56E94FD70F2BCBBCE6")
        XCTAssertEqual(stamp.policy, "0.4.0.2023.1.1")
        XCTAssertTrue(stamp.qualified)
        XCTAssertEqual(stamp.response, sectigo)
    }

    func testAnAnswerThatIsNotQualifiedSaysSo() throws {
        let stamp = try TrustedTime.stamp(from: freeTSA, sha256: fingerprint, nonce: nonce)
        XCTAssertEqual(stamp.time, Date(timeIntervalSince1970: 1795782913))
        XCTAssertNil(stamp.accuracy)
        XCTAssertEqual(stamp.serial, "0AB29F1F")
        XCTAssertFalse(stamp.qualified)
    }

    func testAnAnswerAboutAnotherFileIsRefused() {
        XCTAssertThrowsError(try TrustedTime.stamp(from: sectigo, sha256: Data(count: 32), nonce: nonce)) {
            XCTAssertEqual($0 as? TrustedTime.Failure, .otherFile)
        }
    }

    func testAnAnswerToAnotherQuestionIsRefused() {
        XCTAssertThrowsError(try TrustedTime.stamp(from: sectigo, sha256: fingerprint, nonce: Data([1, 2, 3]))) {
            XCTAssertEqual($0 as? TrustedTime.Failure, .otherQuestion)
        }
    }

    func testARefusalGivesItsStatus() {
        // status: rejection (2), and no token.
        let refusal = Data([0x30, 0x05, 0x30, 0x03, 0x02, 0x01, 0x02])
        XCTAssertThrowsError(try TrustedTime.stamp(from: refusal, sha256: fingerprint, nonce: nonce)) {
            XCTAssertEqual($0 as? TrustedTime.Failure, .refused(2))
        }
    }

    func testAnythingElseIsMalformed() {
        for broken in [Data(), Data([0x30]), Data([0x30, 0x05, 0x30]), Data(sectigo.prefix(200)), Data("<html>".utf8)] {
            XCTAssertThrowsError(try TrustedTime.stamp(from: broken, sha256: fingerprint, nonce: nonce)) {
                XCTAssertEqual($0 as? TrustedTime.Failure, .malformed)
            }
        }
    }

    func testTimesWithAFractionOfASecond() {
        let time = TrustedTime.generalizedTime(Array("20261127122852.25Z".utf8)[...])
        XCTAssertEqual(time, Date(timeIntervalSince1970: 1795782532.25))
        XCTAssertNil(TrustedTime.generalizedTime(Array("20261127122852".utf8)[...]))
        XCTAssertNil(TrustedTime.generalizedTime(Array("2026112712285Z".utf8)[...]))
    }

    func testTheFirstAuthorityIsTheQualifiedOne() {
        XCTAssertEqual(TrustedTime.authorities.first?.url.absoluteString, "https://timestamp.sectigo.com/qualified")
        XCTAssertTrue(TrustedTime.authorities.allSatisfy { $0.url.scheme == "https" })
    }

    // MARK: Answers kept

    private let sectigo = Data(base64Encoded: """
        MIIRrzADAgEAMIIRpgYJKoZIhvcNAQcCoIIRlzCCEZMCAQMxDzANBglghkgBZQMEAgIFADCCARIGCyqGSIb3DQEJEAEEoIIBAQSB
        /jCB+wIBAQYGBACPZwEBMDEwDQYJYIZIAWUDBAIBBQAEIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fAhUA6mvBtJt8
        Q3oyyI5W6U/XDyvLvOYYDzIwMjYxMTI3MTIzNTEyWjADAgEBAgkAigECAwQFBgegY6RhMF8xCzAJBgNVBAYTAkVTMRwwGgYDVQQK
        ExNTZWN0aWdvIChFdXJvcGUpIFNMMTIwMAYDVQQDDClTZWN0aWdvIFF1YWxpZmllZCBUaW1lIFN0YW1waW5nIFNpZ25lciAjM6Ee
        MBwGCCsGAQUFBwEDAQEABA0wCzAJBgcEAIGXXgEBoIIMhTCCBlUwggS9oAMCAQICEGYKmPFOFbLsg8WVgb7S4DgwDQYJKoZIhvcN
        AQEMBQAwXDELMAkGA1UEBhMCRVMxHDAaBgNVBAoTE1NlY3RpZ28gKEV1cm9wZSkgU0wxLzAtBgNVBAMTJlNlY3RpZ28gUXVhbGlm
        aWVkIFRpbWUgU3RhbXBpbmcgQ0EgUjM1MB4XDTIzMDUwMzAwMDAwMFoXDTM0MDgwMjIzNTk1OVowXzELMAkGA1UEBhMCRVMxHDAa
        BgNVBAoTE1NlY3RpZ28gKEV1cm9wZSkgU0wxMjAwBgNVBAMMKVNlY3RpZ28gUXVhbGlmaWVkIFRpbWUgU3RhbXBpbmcgU2lnbmVy
        ICMzMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAmHcGYVbEJHx9hLLUpqBT5RfSkWefjkBbjhEfnxWrPwqYuCjXmtRT
        5XOGyj3s7y+xHkI93XKtAgEj47LSHWcredC8lZYJJs8NZH0oCJcIbPKtSRiJnABesyqE3XWumtd3ZikBtHkUvLIKXhFficgdLE7M
        Sn1fTz2vaup4isZ85vvziyrTDC/sWSDdR6RAnFCcmg5NLXJbVBDycCzCvw6Vk+Rr0u7oXWP2JcEt3w7PwjDEoFMkXkg3cKg0sxnD
        UQ9dxnbZ29hy+919abkPqx36ds/dpCPfix/g530ZEf0uhCumJjOWzQvxIn+AerNDovcayvxGzeHgOkvUYzUmgrfuK9nrCN/7M3oi
        NJTV65div+DPGRHOMeI+Ut4M0GfEBuIssGFEN+l+K2LXaf35FZK+t0syhJO7/EeQmis1yXQtombDuwO4qdR63GIldmjOKk81zpeW
        vwllaZv7E0sqljNIWzPbzF9D6Qkz35fMOnm5/fPEifCAqNll78HOd29ZfONtrWCMSO5qjdbEYCHYTN0LVowk1/mGz/ZJC2tQKoMP
        wNhb1QY2OCryJLl31wFlWJYR5+ElsUwhMsWjlfyTjPsJnT5XzX3UXbxAwEVtmQSkR+eB/p0VUNjpCB26xACyDngIFzD8OoPAFN3r
        d7FWTYhavp3Hpe3f68TSS2ZsGdv9lhUCAwEAAaOCAY4wggGKMB8GA1UdIwQYMBaAFGEAP3fZ/+o50pGlHL6dNcd4XqRnMB0GA1Ud
        DgQWBBQ3UQ8ZvSbf5tVK0GGxcj0C/BhLFjAOBgNVHQ8BAf8EBAMCBsAwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEF
        BQcDCDBEBgNVHSAEPTA7MDkGCysGAQQBsjEBAgEJMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vc2VjdGlnby5jb20vZUlEQVNDUFMw
        TQYDVR0fBEYwRDBCoECgPoY8aHR0cDovL2NybC5zZWN0aWdvLmNvbS9TZWN0aWdvUXVhbGlmaWVkVGltZVN0YW1waW5nQ0FSMzUu
        Y3JsMH0GCCsGAQUFBwEBBHEwbzBIBggrBgEFBQcwAoY8aHR0cDovL2NydC5zZWN0aWdvLmNvbS9TZWN0aWdvUXVhbGlmaWVkVGlt
        ZVN0YW1waW5nQ0FSMzUuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAYEA
        GvbGVBP2wfS3Hpj35iYtMpOkkA624pyQecDshrCgPivtl1af5eYIlIu/VTQ5aqvoEtZXA5dV+XxtvKusDpzJ5u4W7aTATr+3hrI/
        3Q1bBhEINWBZX82axlcteHqxJu8PZcpkbhISxi/2AwiSDaOX8rJgGuUtlaByYYxGhTNZBoLDiy/In21DuuRV8BSGpgnfePOumwr7
        QESuYtk5WIcpBRprmveQjrcrjjL8fyAHVgnvX2VTsQJ0sGhONtpeQVSGotb44znnFwrn+febg4t9tkpF6MdRTt7vVkgOXAffdiu3
        GZSEHHU5rOFmy+pk5RWk1Nm+rk/DdbcInd1X5+r6MnCRBeMd03YjPm2x/nk3AvICt6vBCH/TtdXF+/wWozfSIRd8zaQWd4P9XTgV
        E7Uvn/eSWAL3h/4WNioFzASgopuuKkG7Xg1ZtPm1RssQg9h3cAqV7JRUrpB1nbVrisT7WW+/rBs32gxeeIghdXLB9gdTdJmOHs7g
        VsusAnYJ+ydcMIIGKDCCBBCgAwIBAgIQDNqDAdPzKA5xzbAoo1LGWzANBgkqhkiG9w0BAQwFADBeMQswCQYDVQQGEwJFUzEcMBoG
        A1UEChMTU2VjdGlnbyAoRXVyb3BlKSBTTDExMC8GA1UEAxMoU2VjdGlnbyBRdWFsaWZpZWQgVGltZSBTdGFtcGluZyBSb290IFI0
        NTAeFw0yMDEwMDUwMDAwMDBaFw0zNTEwMDQyMzU5NTlaMFwxCzAJBgNVBAYTAkVTMRwwGgYDVQQKExNTZWN0aWdvIChFdXJvcGUp
        IFNMMS8wLQYDVQQDEyZTZWN0aWdvIFF1YWxpZmllZCBUaW1lIFN0YW1waW5nIENBIFIzNTCCAaIwDQYJKoZIhvcNAQEBBQADggGP
        ADCCAYoCggGBAIGXjuY4bMcH4zfMnKyiI8bc1YG1r8kMzKHGFUv/OUub4wrzLQPQtIwYsiWHPpg2m5MCzKSeukDGqas4qgUlF/6h
        ubH6oTgF2QQikREw2nQrV8PFTZIVE8lObaZCurwwn4lppJmUL1WoqLxHZClrvTSEUYlsF1ZVqDXe5jyKS4PBc83dLroEn6nuITBh
        E+z5DGCv97HV3UhMcIJMuKTZmQrtiUjH0ozg3lnzVPI2T8y3A17APyWJbLmsf3waY54vIGq0rAdLLbbwPRUGWYHZU4W7nkgJfIiL
        QIfa+d0T/1FG4yPJXTWK1wnLZC6lDXUbfZSOxoP2eQC20g7Mz6jRlGPdYQJqVaIGajPrEUYuiNJ+AuYQnMDMItwMqrv8BjygtElg
        /wm9lg1GBK4J2gbsZY4PYmZVkFTecockAsF0Tdf7nsdMbTw5Ta7fFyNDohdSq0jgB3L19X8SjTQYC99beCY1RPU3B9ZG02Zrl6yi
        PVORLbbULioWavwK56L0TLdDywIDAQABo4IBYjCCAV4wHwYDVR0jBBgwFoAUWYGow4Vk5+NEpGlSJpRT9jsN7t4wHQYDVR0OBBYE
        FGEAP3fZ/+o50pGlHL6dNcd4XqRnMA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMBMGA1UdJQQMMAoGCCsGAQUF
        BwMIMBEGA1UdIAQKMAgwBgYEVR0gADBPBgNVHR8ESDBGMESgQqBAhj5odHRwOi8vY3JsLnNlY3RpZ28uY29tL1NlY3RpZ29RdWFs
        aWZpZWRUaW1lU3RhbXBpbmdSb290UjQ1LmNybDB/BggrBgEFBQcBAQRzMHEwSgYIKwYBBQUHMAKGPmh0dHA6Ly9jcnQuc2VjdGln
        by5jb20vU2VjdGlnb1F1YWxpZmllZFRpbWVTdGFtcGluZ1Jvb3RSNDUuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0
        aWdvLmNvbTANBgkqhkiG9w0BAQwFAAOCAgEAGKD7dlJ2eo2soxTBIqBkTHErw6HmVmrdjKjivyVzyKeU1V9GUzLKG5YwIx1zuSiU
        8Mg2vwb4MZmSI7278CBZAEnGyJ745e8zdFmLb4N/I9HvYGh/4YHCWEGBOkJF2Viuctf4JszgyGgEixEKDqEN79sLy5HlUyEQbkXE
        ShYePAPH0IdioWor4wdWw4JvcWgt7N88KD7bjNf2dfQCEEcLTtbcVtg06xdL7Bq942zCEOeAS3tVfef1fvLMjrIMOu2yjCXqK7Qj
        aYqYiZFJ5FAKPioZdHKWYe22XQrtkvB6kBkIktdT7WG/toLkNQszK4w8mVFSFx0V7h97nh1Q9VtOt0s/2AJshPOt0KBE0Z6FD88e
        N6pZ11J/1owa0x41+BPBhcQSG7jVt9VCml3saGiO787VADMzJldVr5wb9mGmO8mByW6VIRE+VAgyY7AYDLJxftzvjptVQPM63Hki
        lqxib7WfTAHqLb8gEEZmJc2Hcit10i2q8xlgLD8ADWckMkhQVKjJuI1RzTQshOFHDTC+ZvuAthQ+7EnTfnBsVXQOtSqo7j6NWa6S
        AoDHoXxjPBi92xxmgMeO9cmf1kTKPgdNYLyCcOcXaryDLpRQbJkorzbEJULq6i53cQsdTbeu5gPYoH+xUiuOGzTMPtZh2IJJMGOP
        kAcLEwgZGkdIzf4i97UxggPcMIID2AIBATBwMFwxCzAJBgNVBAYTAkVTMRwwGgYDVQQKExNTZWN0aWdvIChFdXJvcGUpIFNMMS8w
        LQYDVQQDEyZTZWN0aWdvIFF1YWxpZmllZCBUaW1lIFN0YW1waW5nIENBIFIzNQIQZgqY8U4VsuyDxZWBvtLgODANBglghkgBZQME
        AgIFAKCCAT0wGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNjExMjcxMjM1MTJaMD8GCSqGSIb3
        DQEJBDEyBDAbs9WhWrxqfmLTVdG6fgr2FmK53WeHA2O5kgHHhN1PB0cK/4SVzn1iWx7ozJGGJOowgb8GCyqGSIb3DQEJEAIMMYGv
        MIGsMIGpMBYEFLluSGINhuKJtqY3JGOxEuJmV4i9MIGOBBQdYxi1t9m6Ng11eslViBvxfHUHZjB2MGKkYDBeMQswCQYDVQQGEwJF
        UzEcMBoGA1UEChMTU2VjdGlnbyAoRXVyb3BlKSBTTDExMC8GA1UEAxMoU2VjdGlnbyBRdWFsaWZpZWQgVGltZSBTdGFtcGluZyBS
        b290IFI0NQIQDNqDAdPzKA5xzbAoo1LGWzANBgkqhkiG9w0BAQEFAASCAgBa3Ypj0L0bOBEsX0bH1Wq4mrhViZCBWQ0BbYbaQ7CG
        qS782/eOdtmHOPlcRN/HdTakHScQmplHij30UbT8L8V633Aa0dQrRf6qkCJIVWBAlxcmQnFTVLIOe6Jg6ah+jnqMGPAEKXgXDaw0
        qBJHv/HD0lsaRVuJtBwVVtepdM91pdNtd4mqaxNYF3ZXQTuCswVPOS25zIwziRLn9jhpwPR0DwnqDBivVbz9fdnPrqrunKIgtY9T
        1kXnJ+UaaqJ54rxFQavrCuuIp7roePRBxxMaZaovxA4PkKN8opSx0fh9Jukss8UxPUqfoPxOjHbuQEQaBCJ/xa5WGXoVVeRoXmmf
        adBySKHthekEoU4LfliB8mwHXmlJKaGFBxmrGcULk+WsUbIoBCSoytn1JNi08kSMo6G092XwyQ5+Gip0556/6Rrjb/7Oe9eGZJwV
        I+FekTJQXkKRqNS1AnRNIfhtN5CKw8hNo8Hv4jpgCgt0hYIwPMr9j64sObV5Fee+gPXcbOGlMeClOYACMRzugGayAHDI3T9E8K1a
        7yq4tBFeRd/3VnW/2mYr2EiWNI86ZQ5SweJr7qjf4X8/WSb71HYWJmmroaAZwqq4cwLW4ToThXRJKPco/R5NDNOsyTZ/ogq65nBH
        /FM9p0Lf+h3aPcxmI4ZxB4lgHd47dViUwTp5L7wcSQ==
        """, options: .ignoreUnknownCharacters)!

    private let freeTSA = Data(base64Encoded: """
        MIISIDADAgEAMIISFwYJKoZIhvcNAQcCoIISCDCCEgQCAQMxDzANBglghkgBZQMEAgMFADCCAZEGCyqGSIb3DQEJEAEEoIIBgASC
        AXwwggF4AgEBBgQqAwQBMDEwDQYJYIZIAWUDBAIBBQAEIAABAgMEBQYHCAkKCwwNDg8QERITFBUWFxgZGhscHR4fAgQKsp8fGA8y
        MDI2MTEyNzEyMzUxM1oBAf8CCQCKAQIDBAUGB6CCAROkggEPMIIBCzERMA8GA1UECgwIRnJlZSBUU0ExDDAKBgNVBAsMA1RTQTF2
        MHQGA1UEDQxtVGhpcyBjZXJ0aWZpY2F0ZSBkaWdpdGFsbHkgc2lnbnMgZG9jdW1lbnRzIGFuZCB0aW1lIHN0YW1wIHJlcXVlc3Rz
        IG1hZGUgdXNpbmcgdGhlIGZyZWV0c2Eub3JnIG9ubGluZSBzZXJ2aWNlczEYMBYGA1UEAwwPd3d3LmZyZWV0c2Eub3JnMSQwIgYJ
        KoZIhvcNAQkBFhVidXNpbGV6YXNAbWFpbGJveC5vcmcxEjAQBgNVBAcMCVd1ZXJ6YnVyZzELMAkGA1UEBhMCREUxDzANBgNVBAgM
        BkJheWVybqCCDmcwggZgMIIESKADAgECAgkAwumGFg2o6c0wDQYJKoZIhvcNAQENBQAwgZUxETAPBgNVBAoTCEZyZWUgVFNBMRAw
        DgYDVQQLEwdSb290IENBMRgwFgYDVQQDEw93d3cuZnJlZXRzYS5vcmcxIjAgBgkqhkiG9w0BCQEWE2J1c2lsZXphc0BnbWFpbC5j
        b20xEjAQBgNVBAcTCVd1ZXJ6YnVyZzEPMA0GA1UECBMGQmF5ZXJuMQswCQYDVQQGEwJERTAeFw0yNjAyMTUxOTQ0MjJaFw00MDAy
        MDIxOTQ0MjJaMIIBCzERMA8GA1UECgwIRnJlZSBUU0ExDDAKBgNVBAsMA1RTQTF2MHQGA1UEDQxtVGhpcyBjZXJ0aWZpY2F0ZSBk
        aWdpdGFsbHkgc2lnbnMgZG9jdW1lbnRzIGFuZCB0aW1lIHN0YW1wIHJlcXVlc3RzIG1hZGUgdXNpbmcgdGhlIGZyZWV0c2Eub3Jn
        IG9ubGluZSBzZXJ2aWNlczEYMBYGA1UEAwwPd3d3LmZyZWV0c2Eub3JnMSQwIgYJKoZIhvcNAQkBFhVidXNpbGV6YXNAbWFpbGJv
        eC5vcmcxEjAQBgNVBAcMCVd1ZXJ6YnVyZzELMAkGA1UEBhMCREUxDzANBgNVBAgMBkJheWVybjB2MBAGByqGSM49AgEGBSuBBAAi
        A2IABKIV4aGy1suHGLHSjhQC6Y1LAdRSU57cMG+zx9iznzTAANbn2ioZILHXlunrVNKZeTAubUlbjxedssuLM/pm2Ny+yFXcf27P
        ZtLneyANeGDXAtsiEC2toL58cLK0d65Vq6OCAeYwggHiMAkGA1UdEwQCMAAwHQYDVR0OBBYEFBXAvSbr1F2C0V2TJjEv73Cyi0Ze
        MB8GA1UdIwQYMBaAFPpVDYw0ZlFDTPfns6dsla965qSXMAsGA1UdDwQEAwIGwDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDBsBggr
        BgEFBQcBAQRgMF4wMwYIKwYBBQUHMAKGJ2h0dHA6Ly93d3cuZnJlZXRzYS5vcmcvZmlsZXMvY2FjZXJ0LnBlbTAnBggrBgEFBQcw
        AYYbaHR0cDovL3d3dy5mcmVldHNhLm9yZzoyNTYwMDcGA1UdHwQwMC4wLKAqoCiGJmh0dHA6Ly93d3cuZnJlZXRzYS5vcmcvY3Js
        L3Jvb3RfY2EuY3JsMIHIBgNVHSAEgcAwgb0wgboGAysFCDCBsjAzBggrBgEFBQcCARYnaHR0cDovL3d3dy5mcmVldHNhLm9yZy9m
        cmVldHNhX2Nwcy5odG1sMDIGCCsGAQUFBwIBFiZodHRwOi8vd3d3LmZyZWV0c2Eub3JnL2ZyZWV0c2FfY3BzLnBkZjBHBggrBgEF
        BQcCAjA7GjlGcmVlVFNBIHRydXN0ZWQgdGltZXN0YW1waW5nIFNvZnR3YXJlIGFzIGEgU2VydmljZSAoU2FhUykwDQYJKoZIhvcN
        AQENBQADggIBAGsxVL9h+d8yvTOJmd6wFQ6sM1Gs02C3ciAw0PA2HCXqgpYdUiGVicz/luiWN9ullMBuq/EcjfO1PT+zDFA6pNq3
        moElEBj9UfWf9Pgz24ONK67ep+HRkfk8v0Q2qhVbjiLk1P/OdB6/YwZc4AfDP2RnDDPP0wVfqFsaEGpZr6eUCpvtjvYoXOPfebU5
        UfFXZaXhgP1/3VtlMWlQQZbgq1uSbGl/+IYg9p/hYemgFb87oTOh8wpiXPjJfIQGHTBFFXJeW0uuP4wUeqF74+wwGWWr90Jo7hb8
        X4C4cSW7tpRhYwBJ6WmFYAmJSw0yvkcCh4JJKCKWp/UJKhYL6Tp7jffgXKb4jLhywx7H48bitJ2pclVD4BYR1FqNI8qHvIN+k2R2
        c7rKpAn+1J3XVdDlwvQz2Na4IPXMeWAD675HZyvLfKjbeMPupMYuFmpS9cLJaKAffT9D9FeOMPCtzgMmJD6BFjQWF1NiqW+AwE+v
        gtwkqc2SyK92P6RvPttVJusEDNGJrMr2XzjX/lcy0/0G8PSEoKlAW8/09KAILwRCcqqBJ7boVIkFoBBwDlOcrw0XiORsSUHF//PK
        Hs/ciMeyjfmO2BRYPX+K2D0ElZthTAni18gukHYXTBuTUZxkMINmjJbdd/e2sCnP9l33eAXeOhz0eH1EW94pHNZDt11S3d6BMIIH
        /zCCBeegAwIBAgIJAMHphhYNqOmAMA0GCSqGSIb3DQEBDQUAMIGVMREwDwYDVQQKEwhGcmVlIFRTQTEQMA4GA1UECxMHUm9vdCBD
        QTEYMBYGA1UEAxMPd3d3LmZyZWV0c2Eub3JnMSIwIAYJKoZIhvcNAQkBFhNidXNpbGV6YXNAZ21haWwuY29tMRIwEAYDVQQHEwlX
        dWVyemJ1cmcxDzANBgNVBAgTBkJheWVybjELMAkGA1UEBhMCREUwHhcNMTYwMzEzMDE1MjEzWhcNNDEwMzA3MDE1MjEzWjCBlTER
        MA8GA1UEChMIRnJlZSBUU0ExEDAOBgNVBAsTB1Jvb3QgQ0ExGDAWBgNVBAMTD3d3dy5mcmVldHNhLm9yZzEiMCAGCSqGSIb3DQEJ
        ARYTYnVzaWxlemFzQGdtYWlsLmNvbTESMBAGA1UEBxMJV3VlcnpidXJnMQ8wDQYDVQQIEwZCYXllcm4xCzAJBgNVBAYTAkRFMIIC
        IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtgKODjAy8REQ2WTNqUudAnjhlCrpE6qlmQfNppeTmVvZrH4zutn+NwTaHAGp
        jSGv4/WRpZ1wZ3BRZ5mPUBZyLgq0YrIfQ5Fx0s/MRZPzc1r3lKWrMR9sAQx4mN4z11xFEO529L0dFJjPF9MD8Gpd2feWzGyptlel
        b+PqT+++fOa2oY0+NaMM7l/xcNHPOaMz0/2olk0i22hbKeVhvokPCqhFhzsuhKsmq4Of/o+t6dI7sx5h0nPMm4gGSRhfq+z6BTRg
        CrqQG2FOLoVFgt6iIm/BnNffUr7VDYd3zZmIwFOj/H3DKHoGik/xK3E82YA2ZulVOFRW/zj4ApjPa5OFbpIkd0pmzxzdEcL479hS
        A9dFiyVmSxPtY5ze1P+BE9bMU1PScpRzw8MHFXxyKqW13Qv7LWw4sbk3SciB7GACbQiVGzgkvXG6y85HOuvWNvC5GLSiyP9GlPB0
        V68tbxz4JVTRdw/Xn/XTFNzRBM3cq8lBOAVt/PAX5+uFcv1S9wFE8YjaBfWCP1jdBil+c4e+0tdywT2oJmYBBF/kEt1wmGwMmHun
        NEuQNzh1FtJY54hbUfiWi38mASE7xMtMhfj/C4SvapiDN837gYaPfs8x3KZxbX7C3YAsFnJinlwAUss1fdKar8Q/YVs7H/nU4c4I
        xxxz4f67fcVqM2ITKentbCMCAwEAAaOCAk4wggJKMAwGA1UdEwQFMAMBAf8wDgYDVR0PAQH/BAQDAgHGMB0GA1UdDgQWBBT6VQ2M
        NGZRQ0z357OnbJWveuaklzCBygYDVR0jBIHCMIG/gBT6VQ2MNGZRQ0z357OnbJWveuakl6GBm6SBmDCBlTERMA8GA1UEChMIRnJl
        ZSBUU0ExEDAOBgNVBAsTB1Jvb3QgQ0ExGDAWBgNVBAMTD3d3dy5mcmVldHNhLm9yZzEiMCAGCSqGSIb3DQEJARYTYnVzaWxlemFz
        QGdtYWlsLmNvbTESMBAGA1UEBxMJV3VlcnpidXJnMQ8wDQYDVQQIEwZCYXllcm4xCzAJBgNVBAYTAkRFggkAwemGFg2o6YAwMwYD
        VR0fBCwwKjAooCagJIYiaHR0cDovL3d3dy5mcmVldHNhLm9yZy9yb290X2NhLmNybDCBzwYDVR0gBIHHMIHEMIHBBgorBgEEAYHy
        JAEBMIGyMDMGCCsGAQUFBwIBFidodHRwOi8vd3d3LmZyZWV0c2Eub3JnL2ZyZWV0c2FfY3BzLmh0bWwwMgYIKwYBBQUHAgEWJmh0
        dHA6Ly93d3cuZnJlZXRzYS5vcmcvZnJlZXRzYV9jcHMucGRmMEcGCCsGAQUFBwICMDsaOUZyZWVUU0EgdHJ1c3RlZCB0aW1lc3Rh
        bXBpbmcgU29mdHdhcmUgYXMgYSBTZXJ2aWNlIChTYWFTKTA3BggrBgEFBQcBAQQrMCkwJwYIKwYBBQUHMAGGG2h0dHA6Ly93d3cu
        ZnJlZXRzYS5vcmc6MjU2MDANBgkqhkiG9w0BAQ0FAAOCAgEAaK9+v5OFYu9M6ztYC+L69sw1omdyli89lZAfpWMMh9CRmJhM6KBq
        M/ipwoLtnxyxGsbCPhcQjuTvzm+ylN6VwTMmIlVyVSLKYZcdSjt/eCUN+41K7sD7GVmxZBAFILnBDmTGJmLkrU0KuuIpj8lI/E6Z
        6NnmuP2+RAQSHsfBQi6sssnXMo4HOW5gtPO7gDrUpVXID++1P4XndkoKn7Svw5n0zS9fv1hxBcYIHPPQUze2u30bAQt0n0iIyRLz
        aWuhtpAtd7ffwEbASgzB7E+NGF4tpV37e8KiA2xiGSRqT5ndu28fgpOY87gD3ArZDctZvvTCfHdAS5kEO3gnGGeZEVLDmfEsv8TG
        Ja3AljVa5E40IQDsUXpQLi8G+UC41DWZu8EVT4rnYaCw1VX7ShOR1PNCCvjb8S8tfdudd9zhU3gEB0rxdeTy1tVbNLXW99y90xcw
        r1ZIDUwM/xQ/noO8FRhm0LoPC73Ef+J4ZBdrvWwauF3zJe33d4ibxEcb8/pz5WzFkeixYM2nsHhqHsBKw7JPouKNXRnl5IAE1eFm
        qDyC7G/VT7OF669xM6hbUt5G21JE4cNK6NNucS+fzg1JPX0+3VhsYZjj7D5uljRvQXrJ8iHgr/M6j2oLHvTAI2MLdq2qjZFDOCXs
        xBxJpbmLGBx9ow6ZerlUxzws2AWv2pkxggHsMIIB6AIBATCBozCBlTERMA8GA1UEChMIRnJlZSBUU0ExEDAOBgNVBAsTB1Jvb3Qg
        Q0ExGDAWBgNVBAMTD3d3dy5mcmVldHNhLm9yZzEiMCAGCSqGSIb3DQEJARYTYnVzaWxlemFzQGdtYWlsLmNvbTESMBAGA1UEBxMJ
        V3VlcnpidXJnMQ8wDQYDVQQIEwZCYXllcm4xCzAJBgNVBAYTAkRFAgkAwumGFg2o6c0wDQYJYIZIAWUDBAIDBQCggbgwGgYJKoZI
        hvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNjExMjcxMjM1MTNaMCsGCyqGSIb3DQEJEAIMMRwwGjAYMBYE
        FEgf1TxTTThBgMAoZRmgNvmIVEdmME8GCSqGSIb3DQEJBDFCBEBpsd4oLIVhF+dHX2X9PDt5XFxoB2ETrNQkmEOMTdKhqy0CqoDw
        Q17vRqMlZwWx5XPOeF32tPtpJnb6TRNUaZDIMAoGCCqGSM49BAMEBGcwZQIwGoy2B4OC+0ldColw0MfdkIIg0hk3oSDsmriEYSui
        +fj93BBRys5aj9rAOeolLe1cAjEAwapIzq/etyXZFHVsSzFc2v2brb3PYpLSTr9Xvw6n2R1376/hDvFus1su23TWr0t3
        """, options: .ignoreUnknownCharacters)!
}
