import Testing
@testable import Dict_app

struct NumberNormalizerTests {
    private func n(_ text: String) -> String { NumberNormalizer.apply(text) }

    @Test func writesSimpleNumbersAsDigits() {
        #expect(n("I have two cats and ten dogs") == "I have 2 cats and 10 dogs")
        #expect(n("knocked down to twenty") == "knocked down to 20")
        #expect(n("Six people came.") == "6 people came.")
        #expect(n("the count is zero") == "the count is 0")
    }

    @Test func joinsCompoundNumbers() {
        #expect(n("twenty five people") == "25 people")
        #expect(n("Twenty-five people") == "25 people")
        #expect(n("one hundred and five") == "105")
        #expect(n("three hundred twenty one items") == "321 items")
        #expect(n("two thousand five hundred") == "2500")
        #expect(n("fifteen thousand") == "15,000")
        #expect(n("a hundred times") == "100 times")
        #expect(n("a thousand words") == "1000 words")
    }

    @Test func keepsTheScaleWordForRoundMillions() {
        #expect(n("three million users") == "3 million users")
        #expect(n("two point five million") == "2.5 million")
        #expect(n("two million three hundred thousand") == "2,300,000")
    }

    @Test func writesDecimals() {
        #expect(n("version three point five") == "version 3.5")
        #expect(n("pi is three point one four") == "pi is 3.14")
        #expect(n("the point is clear") == "the point is clear")
    }

    @Test func recognizesYears() {
        #expect(n("back in nineteen eighty four") == "back in 1984")
        #expect(n("in twenty twenty six") == "in 2026")
        #expect(n("two thousand twenty six") == "2026")
    }

    @Test func recognizesTimesOnlyWithACue() {
        #expect(n("meet at three thirty") == "meet at 3:30")
        #expect(n("twelve fifteen pm works") == "12:15 pm works")
        #expect(n("room three thirty") == "room 3 30")
    }

    @Test func joinsDigitsReadOneAtATime() {
        #expect(n("call five five five one two one two") == "call 5551212")
        #expect(n("zip four four one one three") == "zip 44113")
        #expect(n("two three") == "2 3")
    }

    @Test func writesOrdinals() {
        #expect(n("the twenty first century") == "the 21st century")
        #expect(n("twenty-second attempt") == "22nd attempt")
        #expect(n("the twentieth time") == "the 20th time")
        #expect(n("the tenth one") == "the 10th one")
        #expect(n("one hundredth of a second") == "100th of a second")
    }

    @Test func leavesLoneSmallOrdinalsAlone() {
        #expect(n("the first thing") == "the first thing")
        #expect(n("wait a second") == "wait a second")
        #expect(n("the third option") == "the third option")
    }

    @Test func leavesALoneOneAlone() {
        #expect(n("this one is better") == "this one is better")
        #expect(n("one of them broke") == "one of them broke")
        #expect(n("Can we add one more?") == "Can we add one more?")
        #expect(n("One thing first.") == "One thing first.")
    }

    @Test func convertsOneNextToAnotherNumber() {
        #expect(n("one or two days") == "1 or 2 days")
        #expect(n("between one and five") == "between 1 and 5")
        #expect(n("one, two, three, go") == "1, 2, 3, go")
        #expect(n("at one thirty") == "at 1:30")
        #expect(n("twenty one") == "21")
    }

    @Test func keepsPunctuationAndSpacingAroundNumbers() {
        #expect(n("\"Twenty five,\" she said.") == "\"25,\" she said.")
        #expect(n("(about forty two)") == "(about 42)")
        #expect(n("First line has two.\n\nSecond has three.") == "First line has 2.\n\nSecond has 3.")
        #expect(n("twenty-one-year-old") == "21-year-old")
    }

    @Test func doesNotCrossPunctuation() {
        #expect(n("I said twenty. Five came.") == "I said 20. 5 came.")
        #expect(n("ten, nine, eight") == "10, 9, 8")
    }

    @Test func leavesTextWithoutNumbersUntouched() {
        let text = "Nothing to see here, hundreds of words and none of them count."
        #expect(n(text) == text)
        #expect(n("") == "")
        #expect(n("a hundred") == "100")
        #expect(n("hundred") == "hundred")
    }
}
