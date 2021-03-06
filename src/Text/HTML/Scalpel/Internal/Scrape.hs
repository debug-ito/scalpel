{-# OPTIONS_HADDOCK hide #-}
module Text.HTML.Scalpel.Internal.Scrape (
    Scraper
,   scrape
,   attr
,   attrs
,   html
,   htmls
,   innerHTML
,   innerHTMLs
,   text
,   texts
,   chroot
,   chroots
) where

import Text.HTML.Scalpel.Internal.Select
import Text.HTML.Scalpel.Internal.Select.Types

import Control.Applicative
import Control.Monad
import Data.Maybe

import qualified Text.HTML.TagSoup as TagSoup
import qualified Text.StringLike as TagSoup


-- | A value of 'Scraper' @a@ defines a web scraper that is capable of consuming
-- a list of 'TagSoup.Tag's and optionally producing a value of type @a@.
newtype Scraper str a = MkScraper {
        scrapeOffsets :: [(TagSoup.Tag str, CloseOffset)] -> Maybe a
    }

instance Functor (Scraper str) where
    fmap f (MkScraper a) = MkScraper $ fmap (fmap f) a

instance Applicative (Scraper str) where
    pure = MkScraper . const . Just
    (MkScraper f) <*> (MkScraper a) = MkScraper applied
        where applied tags | (Just aVal) <- a tags = ($ aVal) <$> f tags
                           | otherwise             = Nothing

instance Alternative (Scraper str) where
    empty = MkScraper $ const Nothing
    (MkScraper a) <|> (MkScraper b) = MkScraper choice
        where choice tags | (Just aVal) <- a tags = Just aVal
                          | otherwise             = b tags

instance Monad (Scraper str) where
    return = pure
    (MkScraper a) >>= f = MkScraper combined
        where combined tags | (Just aVal) <- a tags = let (MkScraper b) = f aVal
                                                      in  b tags
                            | otherwise             = Nothing

instance MonadPlus (Scraper str) where
    mzero = empty
    mplus = (<|>)

-- | The 'scrape' function executes a 'Scraper' on a list of
-- 'TagSoup.Tag's and produces an optional value.
scrape :: (Ord str, TagSoup.StringLike str)
       => Scraper str a -> [TagSoup.Tag str] -> Maybe a
scrape s = scrapeOffsets s . tagWithOffset . TagSoup.canonicalizeTags

-- | The 'chroot' function takes a selector and an inner scraper and executes
-- the inner scraper as if it were scraping a document that consists solely of
-- the tags corresponding to the selector.
--
-- This function will match only the first set of tags matching the selector, to
-- match every set of tags, use 'chroots'.
chroot :: (Ord str, TagSoup.StringLike str, Selectable s)
       => s -> Scraper str a -> Scraper str a
chroot selector (MkScraper inner) = MkScraper
                                  $ join . (inner <$>)
                                  . listToMaybe . select selector

-- | The 'chroots' function takes a selector and an inner scraper and executes
-- the inner scraper as if it were scraping a document that consists solely of
-- the tags corresponding to the selector. The inner scraper is executed for
-- each set of tags matching the given selector.
chroots :: (Ord str, TagSoup.StringLike str, Selectable s)
        => s -> Scraper str a -> Scraper str [a]
chroots selector (MkScraper inner) = MkScraper
                                   $ return . mapMaybe inner . select selector

-- | The 'text' function takes a selector and returns the inner text from the
-- set of tags described by the given selector.
--
-- This function will match only the first set of tags matching the selector, to
-- match every set of tags, use 'texts'.
text :: (Ord str, TagSoup.StringLike str, Selectable s) => s -> Scraper str str
text s = MkScraper $ withHead tagsToText . select_ s

-- | The 'texts' function takes a selector and returns the inner text from every
-- set of tags matching the given selector.
texts :: (Ord str, TagSoup.StringLike str, Selectable s)
      => s -> Scraper str [str]
texts s = MkScraper $ withAll tagsToText . select_ s

-- | The 'html' function takes a selector and returns the html string from the
-- set of tags described by the given selector.
--
-- This function will match only the first set of tags matching the selector, to
-- match every set of tags, use 'htmls'.
html :: (Ord str, TagSoup.StringLike str, Selectable s) => s -> Scraper str str
html s = MkScraper $ withHead tagsToHTML . select_ s

-- | The 'htmls' function takes a selector and returns the html string from
-- every set of tags matching the given selector.
htmls :: (Ord str, TagSoup.StringLike str, Selectable s)
      => s -> Scraper str [str]
htmls s = MkScraper $ withAll tagsToHTML . select_ s

-- | The 'innerHTML' function takes a selector and returns the inner html string
-- from the set of tags described by the given selector. Inner html here meaning
-- the html within but not including the selected tags.
--
-- This function will match only the first set of tags matching the selector, to
-- match every set of tags, use 'innerHTMLs'.
innerHTML :: (Ord str, TagSoup.StringLike str, Selectable s)
          => s -> Scraper str str
innerHTML s = MkScraper $ withHead tagsToInnerHTML . select_ s

-- | The 'innerHTMLs' function takes a selector and returns the inner html
-- string from every set of tags matching the given selector.
innerHTMLs :: (Ord str, TagSoup.StringLike str, Selectable s)
           => s -> Scraper str [str]
innerHTMLs s = MkScraper $ withAll tagsToInnerHTML . select_ s

-- | The 'attr' function takes an attribute name and a selector and returns the
-- value of the attribute of the given name for the first opening tag that
-- matches the given selector.
--
-- This function will match only the opening tag matching the selector, to match
-- every tag, use 'attrs'.
attr :: (Ord str, Show str, TagSoup.StringLike str, Selectable s)
     => String -> s -> Scraper str str
attr name s = MkScraper
            $ join . withHead (tagsToAttr $ TagSoup.castString name) . select_ s

-- | The 'attrs' function takes an attribute name and a selector and returns the
-- value of the attribute of the given name for every opening tag that matches
-- the given selector.
attrs :: (Ord str, Show str, TagSoup.StringLike str, Selectable s)
     => String -> s -> Scraper str [str]
attrs name s = MkScraper
             $ fmap catMaybes . withAll (tagsToAttr nameStr) . select_ s
    where nameStr = TagSoup.castString name

withHead :: (a -> b) -> [a] -> Maybe b
withHead _ []    = Nothing
withHead f (x:_) = Just $ f x

withAll :: (a -> b) -> [a] -> Maybe [b]
withAll _ [] = Nothing
withAll f xs = Just $ map f xs

tagsToText :: TagSoup.StringLike str => [TagSoup.Tag str] -> str
tagsToText = TagSoup.innerText

tagsToHTML :: TagSoup.StringLike str => [TagSoup.Tag str] -> str
tagsToHTML = TagSoup.renderTags

tagsToInnerHTML :: TagSoup.StringLike str => [TagSoup.Tag str] -> str
tagsToInnerHTML = tagsToHTML . reverse . drop 1 . reverse . drop 1

tagsToAttr :: (Show str, TagSoup.StringLike str)
           => str -> [TagSoup.Tag str] -> Maybe str
tagsToAttr attr tags = do
    tag <- listToMaybe tags
    guard $ TagSoup.isTagOpen tag
    return $ TagSoup.fromAttrib attr tag
