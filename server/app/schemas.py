from datetime import date, time, datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from typing import Literal
from pydantic import BaseModel, Field, model_validator, ConfigDict

class PersonInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    display_name: str = Field(min_length=1, max_length=100)
    birth_date: date
    # Optional only when the time is unknown; Ashtakoot is then calculated for 12:00 noon local time.
    birth_time_local: time | None = None
    birth_timezone: str
    birth_place_name: str = Field(min_length=1, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    time_accuracy: Literal['exact','approximate','unknown'] = 'exact'
    fold: Literal[0,1] | None = None
    @model_validator(mode='after')
    def validate_birth(self):
        self.display_name = self.display_name.strip()
        if not self.display_name: raise ValueError('Name is required')
        if self.time_accuracy=='unknown': self.birth_time_local=time(12,0)
        elif self.birth_time_local is None: raise ValueError('Birth time is required unless it is unknown')
        if self.birth_time_local.tzinfo: raise ValueError('Enter local time without offset')
        try: zone = ZoneInfo(self.birth_timezone)
        except ZoneInfoNotFoundError: raise ValueError('Unknown IANA timezone')
        naive = datetime.combine(self.birth_date, self.birth_time_local)
        valid = [f for f in (0,1) if naive.replace(tzinfo=zone, fold=f).astimezone(timezone.utc).astimezone(zone).replace(tzinfo=None) == naive]
        if not valid: raise ValueError('Birth time does not exist due to DST transition')
        if naive.replace(tzinfo=zone,fold=0).utcoffset() != naive.replace(tzinfo=zone,fold=1).utcoffset() and self.fold is None:
            raise ValueError('Ambiguous DST time: select first or second occurrence')
        if self.utc() > datetime.now(timezone.utc): raise ValueError('Birth date cannot be in the future')
        return self
    def utc(self):
        return datetime.combine(self.birth_date,self.birth_time_local).replace(tzinfo=ZoneInfo(self.birth_timezone),fold=self.fold or 0).astimezone(timezone.utc)
    def stored(self): return {**self.model_dump(mode='json'), 'birth_utc':self.utc().isoformat()}
class MatchInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    person1_id: str
    person2_id: str
    locale: Literal['en','hi'] = 'en'
class ComparisonInput(BaseModel):
    person1_id: str
    person2_ids: list[str] = Field(min_length=2,max_length=20)
    locale: Literal['en','hi'] = 'en'
    @model_validator(mode='after')
    def distinct(self):
        if len(set(self.person2_ids)) != len(self.person2_ids) or self.person1_id in self.person2_ids: raise ValueError('Choose distinct candidates other than Person 1')
        return self
class LocaleInput(BaseModel):
    locale: Literal['en','hi'] = 'en'
